import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import 'fullscreen.dart';

import 'main.dart';
import 'net.dart';
import 'remote_navigation.dart';
import 'store.dart';
import 'streams.dart';
import 'theme.dart';
import 'widgets.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.meta, required this.video});
  final Meta meta;
  final String video;
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

/// Re-maximizes once the window has actually left full screen; on macOS that's after the exit animation.
class _PlayerPageState extends State<PlayerPage> with WindowListener {
  late final player = Player(
    configuration: const PlayerConfiguration(title: 'Dremio', bufferSize: 96 * 1024 * 1024),
  );
  late final controller = VideoController(player);
  final store = Store.instance;
  final focus = FocusNode(debugLabel: 'Video'), controls = FocusNode(debugLabel: 'Play/pause');
  final backFocus = FocusNode(debugLabel: 'Player back'), volumeFocus = FocusNode(debugLabel: 'Volume slider'), progressFocus = FocusNode(debugLabel: 'Progress bar');
  final rewindFocus = FocusNode(),
      forwardFocus = FocusNode(),
      audioFocus = FocusNode(),
      subtitlesFocus = FocusNode(),
      sourcesFocus = FocusNode(),
      muteFocus = FocusNode(),
      fullscreenFocus = FocusNode();
  List<FocusNode> get bottomNodes => [rewindFocus, controls, forwardFocus, audioFocus, subtitlesFocus, sourcesFocus, muteFocus, if (desktop) volumeFocus, if (desktop) fullscreenFocus];

  void _focusHud(FocusNode target) {
    _poke();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && target.context != null) target.requestFocus();
    });
  }

  final subs = <StreamSubscription>[];
  List<StreamChoice> choices = [];
  int index = 0, attempt = 0, resumeMs = 0, lastSaved = 0;
  bool completed = false;
  bool ready = false, hadPlayed = false, hasFrames = false, closed = false, hud = true, fullscreen = false, seekedToResume = false, enteredFullscreen = false, buffering = false;
  String? error;
  Timer? hideTimer, stallTimer;
  Duration position = Duration.zero, duration = Duration.zero;
  bool playing = false;
  double volume = 100, unmuted = 100;
  String get type => str(widget.meta, 'type');
  String get title => str(widget.meta, 'name');

  @override
  void initState() {
    super.initState();
    resumeMs = store.getInt('position:${widget.video}');
    volume = store.getInt('volume', 100).clamp(0, 100).toDouble();
    if (volume > 0) unmuted = volume;
    player.setVolume(volume);
    if (desktop) {
      windowManager.addListener(this);
      windowManager.isFullScreen().then((f) {
        if (mounted) setState(() => fullscreen = f);
      });
    }
    focus.addListener(() {
      if (mounted) setState(() {});
    });
    _configure();
    subs.addAll([
      player.stream.playing.listen((p) {
        if (closed) return;
        setState(() => playing = p);
        if (p) _onPlaying();
        if (!p && ready) _savePosition();
        _poke();
      }),
      player.stream.position.listen((p) {
        position = p;
        if (ready && mounted) setState(() {});
        if (ready && store.now() - lastSaved > 10000) _savePosition();
      }),
      player.stream.duration.listen((d) {
        duration = d;
        if (hadPlayed && !seekedToResume && d.inMilliseconds > 0) _resume();
      }),
      player.stream.width.listen((w) {
        if ((w ?? 0) > 0) hasFrames = true;
      }),
      player.stream.error.listen((_) {
        if (closed) return;
        _savePosition();
        _next();
      }),
      player.stream.completed.listen((done) {
        if (!done || closed) return;
        final length = duration.inMilliseconds;
        if (!hadPlayed || (length > 0 && resumeMs < length - 120000 && position.inMilliseconds < length - 120000)) {
          _next();
          return;
        }
        completed = true;
        store.saveProgress(widget.video, 0, 0);
        _exit();
      }),
      player.stream.buffering.listen((b) {
        if (!closed && mounted && b != buffering) setState(() => buffering = b);
      }),
      player.stream.tracks.listen((_) {
        if (mounted) setState(() {});
      }),
    ]);
    _resolve();
  }

  Future<void> _configure() async {
    final native = player.platform;
    if (native is NativePlayer) {
      await native.setProperty('alang', 'en,eng,es');
      await native.setProperty('slang', 'en,eng');
      await native.setProperty('user-agent', userAgent);
      await native.setProperty('network-timeout', '30');
      await native.setProperty('cache', 'yes');
      await native.setProperty('demuxer-max-back-bytes', '67108864');
    }
  }

  Future<void> _resolve() async {
    try {
      final found = await resolveStreams(type, widget.video);
      if (closed) return;
      choices = found;
      index = 0;
      if (found.isEmpty) {
        if (type == 'movie') {
          store.setInt('nostreams:${widget.video}', store.now());
        }
        _fail('No streams found.');
      } else {
        _start();
      }
    } on NoConnection {
      _fail('Connect a source in Settings.');
    } catch (_) {
      _fail('Couldn’t reach ${sourceById(store.defaultSource).name}.');
    }
  }

  Future<void> _start() async {
    if (closed) return;
    if (index >= choices.length) {
      _fail('Couldn’t play this title.');
      return;
    }
    final current = ++attempt;
    final choice = choices[index];
    setState(() {
      ready = false;
      hadPlayed = false;
      hasFrames = false;
      seekedToResume = false;
      error = null;
    });
    stallTimer?.cancel();
    try {
      final address = await preflight(choice);
      if (closed || current != attempt) return;
      await player.open(Media(address, httpHeaders: {'User-Agent': userAgent, ...choice.headers}), play: true);
      stallTimer = Timer(const Duration(seconds: 35), () {
        if (!closed && current == attempt && !hasFrames) _next();
      });
    } catch (_) {
      if (!closed && current == attempt) _next();
    }
  }

  void _next() {
    if (closed) return;
    ready = false;
    index++;
    _start();
  }

  void _onPlaying() {
    if (hadPlayed) return;
    hadPlayed = true;
    ready = true;
    store.recordPlayback(widget.meta, widget.video);
    if (duration.inMilliseconds > 0) _resume();
    setState(() {});
    _poke();
    _addOnlineSubtitles(attempt);
  }

  /// Fills in subtitles when the source has no English track (common with 4K remuxes); they're listed, not switched on.
  Future<void> _addOnlineSubtitles(int current) async {
    final native = player.platform;
    if (native is! NativePlayer) return;
    if (player.state.tracks.subtitle.any((t) => t.id != 'auto' && t.id != 'no' && (t.language ?? '').toLowerCase().startsWith('en'))) {
      return;
    }
    try {
      for (final s in await onlineSubtitles(type, widget.video)) {
        if (closed || current != attempt) return;
        await native.command(['sub-add', s.url, 'auto', s.name, s.language]);
      }
    } catch (_) {}
  }

  void _resume() {
    seekedToResume = true;
    if (resumeMs > 1000) player.seek(Duration(milliseconds: resumeMs));
  }

  void _fail(String message) {
    if (closed) return;
    player.stop();
    setState(() {
      ready = false;
      error = message;
    });
  }

  void _savePosition() {
    if (!ready || completed) return;
    final t = position.inMilliseconds, length = duration.inMilliseconds;
    if (t > 0) {
      resumeMs = t;
      store.saveProgress(widget.video, t, length);
    }
    lastSaved = store.now();
  }

  void _poke() {
    if (!mounted) return;
    if (!hud) setState(() => hud = true);
    hideTimer?.cancel();
    hideTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && ready) _hideHud();
    });
  }

  void _hideHud() {
    hideTimer?.cancel();
    if (inControls) focus.requestFocus();
    setState(() => hud = false);
  }

  void _toggle() {
    if (!ready) return;
    player.playOrPause();
    _poke();
  }

  void _seek(int seconds) {
    if (!ready) return;
    final target = position + Duration(seconds: seconds);
    player.seek(target < Duration.zero ? Duration.zero : (duration > Duration.zero && target > duration ? duration : target));
    _poke();
  }

  /// Leaving the player only undoes full screen it turned on itself, not full screen forced from the main UI.
  Future<void> _setFullscreen(bool value) async {
    if (!desktop) return;
    enteredFullscreen = value && (enteredFullscreen || !fullscreen);
    await FullScreen.set(value);
    if (mounted) setState(() => fullscreen = value);
  }

  @override
  void onWindowEnterFullScreen() {
    if (mounted) setState(() => fullscreen = true);
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted) setState(() => fullscreen = false);
  }

  /// Wheel or two-finger scroll over the video changes the volume; up is louder.
  void _scrollVolume(double dy) {
    if (!ready || dy == 0) return;
    _setVolume(volume - (dy / 4).clamp(-8, 8));
    _poke();
  }

  void _exit() {
    if (enteredFullscreen) _setFullscreen(false);
    final nav = navigatorKey.currentState;
    if (nav != null && nav.canPop()) nav.pop();
  }

  Future<void> _pick<T>(String heading, List<T> options, T? selected, String Function(T) name, void Function(T) choose) async {
    hideTimer?.cancel();
    final previous = FocusManager.instance.primaryFocus;
    final picked = await showDialog<T>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(heading, style: text(18, weight: FontWeight.w500)),
        children: [
          for (final o in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, o),
              child: Row(
                children: [
                  SizedBox(width: 26, child: o == selected ? const Icon(Icons.check, size: 18, color: green) : null),
                  Expanded(
                    child: Text(name(o), style: text(14, color: o == selected ? green : white)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    if (!mounted) return;
    if (picked != null) choose(picked);
    _focusHud(previous ?? controls);
  }

  String _trackName(dynamic t, bool captions) {
    if (t.id == 'auto') return 'Auto';
    if (t.id == 'no') return captions ? 'Off' : 'None';
    final parts = [t.title, t.language].where((s) => s != null && '$s'.isNotEmpty).join(' · ');
    return parts.isEmpty ? 'Track ${t.id}' : parts;
  }

  void _audio() {
    if (!ready) return;
    final tracks = player.state.tracks.audio.where((t) => t.id != 'no').toList();
    _pick<AudioTrack>('Audio', tracks, player.state.track.audio, (t) => _trackName(t, false), player.setAudioTrack);
  }

  void _subtitles() {
    if (!ready) return;
    final tracks = player.state.tracks.subtitle.where((t) => t.id != 'auto').toList();
    _pick<SubtitleTrack>('Subtitles', tracks, player.state.track.subtitle, (t) => _trackName(t, true), player.setSubtitleTrack);
  }

  void _sources() {
    if (choices.isEmpty) return;
    _pick<int>('Sources', List.generate(choices.length, (i) => i), index, (i) => choices[i].label, (i) {
      if (i == index) return;
      _savePosition();
      index = i;
      _start();
    });
  }

  void _setVolume(double v) {
    v = v.clamp(0, 100).roundToDouble();
    if (v > 0) unmuted = v;
    player.setVolume(v);
    store.setInt('volume', v.round());
    setState(() => volume = v);
  }

  void _mute() => _setVolume(volume > 0 ? 0 : unmuted);

  bool get inControls => ready && focus.hasFocus && !focus.hasPrimaryFocus;

  KeyEventResult _key(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.mediaPlayPause || k == LogicalKeyboardKey.mediaPlay || k == LogicalKeyboardKey.mediaPause) {
      _toggle();
      return KeyEventResult.handled;
    }
    if (!focus.hasPrimaryFocus) {
      if (desktop || !inControls) return KeyEventResult.ignored;
      return playerControlStep(k, back: backFocus, play: controls, progress: progressFocus, video: focus, bottom: bottomNodes, request: _focusHud);
    }
    if (!desktop && (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter)) {
      _toggle();
    } else if (!desktop && k == LogicalKeyboardKey.arrowDown) {
      if (!ready) return KeyEventResult.ignored;
      _focusHud(controls);
    } else if (!desktop && k == LogicalKeyboardKey.arrowUp) {
      if (ready) _focusHud(progressFocus);
    } else if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.keyK) {
      _toggle();
    } else if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.keyJ) {
      _seek(-10);
    } else if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.keyL) {
      _seek(10);
    } else if (k == LogicalKeyboardKey.mediaFastForward) {
      _seek(30);
    } else if (k == LogicalKeyboardKey.mediaRewind) {
      _seek(-30);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _setVolume(volume + 10);
      _poke();
    } else if (k == LogicalKeyboardKey.arrowDown) {
      _setVolume(volume - 10);
      _poke();
    } else if (k == LogicalKeyboardKey.keyF) {
      _setFullscreen(!fullscreen);
    } else if (k == LogicalKeyboardKey.keyM) {
      _mute();
      _poke();
    } else if (k == LogicalKeyboardKey.escape) {
      fullscreen ? _setFullscreen(false) : _exit();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    closed = true;
    attempt++;
    _savePosition();
    hideTimer?.cancel();
    stallTimer?.cancel();
    for (final s in subs) {
      s.cancel();
    }
    if (desktop) windowManager.removeListener(this);
    if (enteredFullscreen) FullScreen.set(false);
    player.dispose();
    focus.dispose();
    controls.dispose();
    backFocus.dispose();
    volumeFocus.dispose();
    progressFocus.dispose();
    for (final node in [rewindFocus, forwardFocus, audioFocus, subtitlesFocus, sourcesFocus, muteFocus, fullscreenFocus]) {
      node.dispose();
    }
    super.dispose();
  }

  String _clock(Duration d) {
    final s = d.inSeconds;
    return s >= 3600 ? '${s ~/ 3600}:${(s ~/ 60 % 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}' : '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final showHud = ready && hud;
    return PopScope(
      // On the remote, Back first dismisses the overlay; Escape on desktop keeps its old behavior.
      canPop: desktop ? !inControls : !showHud,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (desktop) {
          focus.requestFocus();
          _poke();
        } else {
          _hideHud();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: focus,
          autofocus: true,
          onKeyEvent: _key,
          child: MouseRegion(
            cursor: showHud ? SystemMouseCursors.basic : SystemMouseCursors.none,
            onHover: (_) => _poke(),
            child: Listener(
              onPointerSignal: (e) {
                if (e is PointerScrollEvent) _scrollVolume(e.scrollDelta.dy);
              },
              onPointerPanZoomUpdate: (e) => _scrollVolume(-e.localPanDelta.dy),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggle,
                onDoubleTap: () => _setFullscreen(!fullscreen),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Video(controller: controller, controls: NoVideoControls, fill: Colors.black),
                    if (!ready) _loading(),
                    // Big files can take a while to fill mpv's cache after playback has nominally started.
                    if (ready && (buffering || duration == Duration.zero)) _buffering(),
                    AnimatedOpacity(
                      opacity: showHud ? 1 : 0,
                      duration: const Duration(milliseconds: 220),
                      child: ExcludeFocus(
                        excluding: !showHud,
                        child: IgnorePointer(ignoring: !showHud, child: _hud()),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _loading() => Container(
    color: const Color(0xf0070c09),
    alignment: Alignment.center,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Logo(size: 52),
        const SizedBox(height: 22),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Text(title, textAlign: TextAlign.center, maxLines: 2, style: text(28)),
        ),
        const SizedBox(height: 28),
        if (error == null)
          const Swirl()
        else ...[
          Text(error!, style: text(15, color: green)),
          const SizedBox(height: 22),
          Pill(icon: Icons.arrow_back_rounded, label: 'Back', autofocus: true, onTap: _exit),
        ],
      ],
    ),
  );

  Widget _buffering() => IgnorePointer(
    child: Center(
      child: Container(
        padding: const EdgeInsets.fromLTRB(26, 22, 26, 18),
        decoration: BoxDecoration(color: const Color(0xb3070c09), borderRadius: BorderRadius.circular(22)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Swirl(size: 40),
            const SizedBox(height: 12),
            Text('Buffering…', style: text(14, color: muted)),
          ],
        ),
      ),
    ),
  );

  Widget _hud() {
    final total = duration.inMilliseconds;
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 120,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xc0070c09), Color(0x00070c09)]),
            ),
            alignment: Alignment.topLeft,
            padding: EdgeInsets.fromLTRB(fullscreen || !desktop ? 40 : 90, 26, 40, 0),
            child: Pill(icon: Icons.arrow_back_rounded, focusNode: backFocus, tooltip: 'Back  (Esc)', height: 44, onTap: _exit),
          ),
        ),
        if (ready)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(48, 50, 48, 26),
              decoration: const BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00070c09), Color(0xc0070c09), Color(0xf5070c09)]),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: text(20)),
                  Row(
                    children: [
                      Expanded(
                        child: RemoteSliderKeys(
                          focusNode: progressFocus,
                          value: total > 0 ? position.inMilliseconds.clamp(0, total).toDouble() : 0,
                          maximum: total > 0 ? total.toDouble() : 1,
                          step: 10000,
                          onActivate: _toggle,
                          onChanged: (value) {
                            if (total <= 0) return;
                            final target = Duration(milliseconds: value.round());
                            setState(() => position = target);
                            player.seek(target);
                            _poke();
                          },
                          child: Slider(
                            value: total > 0 ? position.inMilliseconds.clamp(0, total).toDouble() : 0,
                            max: total > 0 ? total.toDouble() : 1,
                            onChanged: total > 0
                                ? (v) {
                                    setState(() => position = Duration(milliseconds: v.round()));
                                    hideTimer?.cancel();
                                  }
                                : null,
                            onChangeEnd: (v) {
                              player.seek(Duration(milliseconds: v.round()));
                              _poke();
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text('${_clock(position)} / ${_clock(duration)}', style: text(13, color: const Color(0xffcbd6cb))),
                    ],
                  ),
                  const SizedBox(height: 6),
                  FocusTraversalGroup(
                    child: Row(
                      children: [
                        Pill(icon: Icons.replay_10_rounded, focusNode: rewindFocus, tooltip: 'Back 10 seconds  (←)', height: 44, onTap: () => _seek(-10)),
                        const SizedBox(width: 12),
                        Pill(icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded, focusNode: controls, tooltip: playing ? 'Pause  (Space)' : 'Play  (Space)', height: 44, onTap: _toggle),
                        const SizedBox(width: 12),
                        Pill(icon: Icons.forward_10_rounded, focusNode: forwardFocus, tooltip: 'Forward 10 seconds  (→)', height: 44, onTap: () => _seek(10)),
                        const SizedBox(width: 12),
                        Pill(icon: Icons.record_voice_over_rounded, focusNode: audioFocus, tooltip: 'Audio track', height: 44, onTap: _audio),
                        const SizedBox(width: 12),
                        Pill(icon: Icons.subtitles_outlined, focusNode: subtitlesFocus, tooltip: 'Subtitles', height: 44, onTap: _subtitles),
                        const SizedBox(width: 12),
                        Pill(icon: Icons.layers_outlined, focusNode: sourcesFocus, tooltip: 'Sources', height: 44, onTap: _sources),
                        const Spacer(),
                        Pill(
                          icon: volume == 0
                              ? Icons.volume_off_rounded
                              : volume < 50
                              ? Icons.volume_down_rounded
                              : Icons.volume_up_rounded,
                          focusNode: muteFocus,
                          tooltip: volume == 0 ? 'Unmute  (M)' : 'Mute  (M)',
                          height: 44,
                          onTap: _mute,
                        ),
                        // TV remotes have their own volume buttons, so the slider is desktop-only.
                        if (desktop)
                          SizedBox(
                            width: 130,
                            child: RemoteVolumeKeys(
                              focusNode: volumeFocus,
                              onActivate: _mute,
                              value: volume,
                              onChanged: (v) {
                                _setVolume(v);
                                _poke();
                              },
                              child: Slider(
                                value: volume,
                                max: 100,
                                onChanged: (v) {
                                  _setVolume(v);
                                  hideTimer?.cancel();
                                },
                                onChangeEnd: (_) => _poke(),
                              ),
                            ),
                          ),
                        if (desktop) const SizedBox(width: 12),
                        if (desktop)
                          Pill(
                            icon: fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                            focusNode: fullscreenFocus,
                            tooltip: 'Full screen  (F)',
                            height: 44,
                            onTap: () => _setFullscreen(!fullscreen),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
