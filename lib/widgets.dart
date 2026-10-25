import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'artwork_cache.dart';
import 'catalog.dart';
import 'main.dart' show desktop;
import 'store.dart';
import 'theme.dart';

/// Focus or hover lifts the child like a hovering UFO: slight scale, gentle bob, soft green underglow.
class Lift extends StatefulWidget {
  const Lift({
    super.key,
    required this.builder,
    this.onTap,
    this.onKey,
    this.focusNode,
    this.autofocus = false,
    this.glow = false,
    this.scale = 1.045,
    this.onFocus,
  });
  final Widget Function(BuildContext context, bool active) builder;
  final VoidCallback? onTap;
  final KeyEventResult Function(KeyEvent event)? onKey;
  final FocusNode? focusNode;
  final bool autofocus, glow;
  final double scale;
  final ValueChanged<bool>? onFocus;

  @override
  State<Lift> createState() => _LiftState();
}

class _LiftState extends State<Lift> with SingleTickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  bool _focused = false, _hovered = false;
  bool get _active => _focused || _hovered;

  void _update() {
    if (_active) {
      _bob.repeat(reverse: true);
    } else {
      _bob.stop();
      _bob.value = 0;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (f) {
        _focused = f;
        widget.onFocus?.call(f);
        _update();
      },
      onKeyEvent: (node, event) {
        final custom = widget.onKey?.call(event);
        if (custom != null && custom != KeyEventResult.ignored) return custom;
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          widget.onTap?.call();
          return widget.onTap == null
              ? KeyEventResult.ignored
              : KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        cursor: widget.onTap == null
            ? MouseCursor.defer
            : SystemMouseCursors.click,
        onEnter: (_) {
          _hovered = true;
          _update();
        },
        onExit: (_) {
          _hovered = false;
          _update();
        },
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedBuilder(
            animation: _bob,
            builder: (context, child) => Transform.translate(
              offset: Offset(
                0,
                _active ? -2 - 3 * Curves.easeInOut.transform(_bob.value) : 0,
              ),
              child: AnimatedScale(
                scale: _active ? widget.scale : 1,
                duration: const Duration(milliseconds: 190),
                child: child,
              ),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (widget.glow)
                  Positioned(
                    left: -8,
                    right: -8,
                    bottom: -10,
                    height: 22,
                    child: AnimatedOpacity(
                      opacity: _active ? 1 : 0,
                      duration: const Duration(milliseconds: 190),
                      child: const CustomPaint(painter: _UfoGlow()),
                    ),
                  ),
                widget.builder(context, _active),
                if (widget.glow)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: _hovered ? 1 : 0,
                        duration: const Duration(milliseconds: 220),
                        child: const CustomPaint(painter: UfoSpotlight()),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A flattened green radial glow, like light under a hovering saucer.
class _UfoGlow extends CustomPainter {
  const _UfoGlow();
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero), radius = size.width * .46;
    canvas.translate(center.dx, center.dy);
    canvas.scale(1, size.height / (radius * 2));
    canvas.drawCircle(
      Offset.zero,
      radius,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x90bdff59), Color(0x28bdff59), Color(0x00bdff59)],
          stops: [0, .45, 1],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_UfoGlow oldDelegate) => false;
}

/// A beam shining down from a saucer above: narrow and bright at the top, spreading and fading toward the bottom.
class UfoSpotlight extends CustomPainter {
  const UfoSpotlight();
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, top = w * .12;
    final beam = Path()
      ..moveTo(w / 2 - top, 0)
      ..lineTo(w / 2 + top, 0)
      ..lineTo(w, h * .92)
      ..lineTo(0, h * .92)
      ..close();
    canvas.drawPath(
      beam,
      Paint()
        ..blendMode = BlendMode.screen
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x66e9ffc8), Color(0x26bdff59), Color(0x00bdff59)],
          stops: [0, .4, 1],
        ).createShader(Offset.zero & size),
    );
    final source = Rect.fromCenter(
      center: Offset(w / 2, 0),
      width: w * .7,
      height: w * .22,
    );
    canvas.drawOval(
      source,
      Paint()
        ..blendMode = BlendMode.screen
        ..shader = const RadialGradient(
          colors: [Color(0x80f4ffe0), Color(0x00bdff59)],
        ).createShader(source),
    );
  }

  @override
  bool shouldRepaint(UfoSpotlight oldDelegate) => false;
}

class Pill extends StatelessWidget {
  const Pill({
    super.key,
    this.label,
    this.icon,
    this.primary = false,
    required this.onTap,
    this.focusNode,
    this.autofocus = false,
    this.onKey,
    this.tooltip,
    this.height = 46,
  });
  final String? label;
  final IconData? icon;
  final bool primary, autofocus;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final KeyEventResult Function(KeyEvent event)? onKey;
  final String? tooltip;
  final double height;

  @override
  Widget build(BuildContext context) {
    final pill = Lift(
      onTap: onTap,
      focusNode: focusNode,
      autofocus: autofocus,
      onKey: onKey,
      builder: (context, active) {
        final fg = active || primary ? ink : white;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: height,
          width: label == null ? height : null,
          padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 22),
          decoration: BoxDecoration(
            color: active
                ? const Color(0xffd5ff91)
                : (primary ? green : const Color(0xcc202b23)),
            borderRadius: BorderRadius.circular(height / 2),
          ),
          child: Row(
            mainAxisSize: label == null ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null)
                Icon(icon, size: label == null ? 24 : 20, color: fg),
              if (icon != null && label != null) const SizedBox(width: 8),
              if (label != null)
                Text(
                  label!,
                  style: text(14, color: fg, weight: FontWeight.w500),
                ),
            ],
          ),
        );
      },
    );
    return tooltip == null
        ? pill
        : Tooltip(
            message: tooltip!,
            waitDuration: const Duration(milliseconds: 600),
            child: pill,
          );
  }
}

class Logo extends StatelessWidget {
  const Logo({super.key, this.size = 27});
  final double size;
  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/dremio-mark.svg',
    height: size,
    width: size * 48 / 56,
  );
}

/// The launch logo bobbing and rocking over its glow. Geometry matches the Android launch drawable so the hand-off doesn't jump.
class HoverLogo extends StatefulWidget {
  const HoverLogo({super.key});
  @override
  State<HoverLogo> createState() => _HoverLogoState();
}

class _HoverLogoState extends State<HoverLogo>
    with SingleTickerProviderStateMixin {
  late final clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat();
  final watch = Stopwatch()..start();

  @override
  void dispose() {
    clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: clock,
    builder: (context, _) {
      final ms = watch.elapsedMilliseconds;
      final bob = math.sin(ms / 1800 * 2 * math.pi),
          rock = math.sin(ms / 2600 * 2 * math.pi);
      return SizedBox(
        width: 72,
        height: 108,
        child: Stack(
          children: [
            Positioned(
              left: 21,
              right: 21,
              top: 99.3,
              height: 5.4,
              child: Transform.scale(
                scaleX: 1 - .2 * bob,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0x33bdff59),
                    borderRadius: BorderRadius.all(Radius.elliptical(15, 2.7)),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Transform.translate(
                offset: Offset(0, -4.5 * bob),
                child: Transform.rotate(
                  angle: 6 * rock * math.pi / 180,
                  child: const Center(child: Logo(size: 84)),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// A green arc with a fading tail, spinning.
class Swirl extends StatefulWidget {
  const Swirl({super.key, this.size = 44});
  final double size;
  @override
  State<Swirl> createState() => _SwirlState();
}

class _SwirlState extends State<Swirl> with SingleTickerProviderStateMixin {
  late final spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
    turns: spin,
    child: CustomPaint(
      size: Size.square(widget.size),
      painter: _SwirlPainter(),
    ),
  );
}

class _SwirlPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 3.5;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        colors: [Color(0x00bdff59), green],
        stops: [0.1, 0.85],
      ).createShader(rect);
    canvas.drawArc(rect, 0.35, 5.2, false, paint);
  }

  @override
  bool shouldRepaint(_SwirlPainter oldDelegate) => false;
}

class Artwork extends StatelessWidget {
  const Artwork(
    this.url, {
    super.key,
    this.width,
    this.radius = 7,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
  });
  final String url;
  final double? width;
  final double radius;
  final BoxFit fit;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final decodeWidth = width ?? MediaQuery.sizeOf(context).width;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: ColoredBox(
        color: artwork,
        child: url.startsWith('https://')
            ? Image(
                image: artworkProvider(url, decodeWidth, ratio),
                fit: fit,
                alignment: alignment,
                width: double.infinity,
                height: double.infinity,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const SizedBox.expand(),
                frameBuilder: (context, child, frame, sync) => sync
                    ? child
                    : AnimatedOpacity(
                        opacity: frame == null ? 0 : 1,
                        duration: const Duration(milliseconds: 260),
                        child: child,
                      ),
              )
            : const SizedBox.expand(),
      ),
    );
  }
}

String posterOf(Meta m) => str(m, 'poster').startsWith('https://')
    ? str(m, 'poster')
    : str(m, 'background');

class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.meta,
    required this.width,
    required this.onOpen,
    this.showEpisode = false,
  });
  final bool showEpisode;
  final Meta meta;
  final double width;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: Store.instance.playbackChanges,
    builder: (context, _, _) => _buildCard(context),
  );

  Widget _buildCard(BuildContext context) {
    final progress = Store.instance.progress(meta);
    final saved = Store.instance.saved(meta);
    return SizedBox(
      width: width,
      child: Lift(
        onTap: onOpen,
        glow: true,
        builder: (context, active) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: width * 1.48,
              child: Stack(
                children: [
                  Positioned.fill(child: Artwork(posterOf(meta), width: width)),
                  if (progress.hasProgress)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(7),
                        ),
                        child: LinearProgressIndicator(
                          key: ValueKey('poster-progress:${str(meta, "id")}'),
                          value: progress.fraction,
                          minHeight: 4,
                          color: green,
                          backgroundColor: const Color(0xb0070c09),
                        ),
                      ),
                    ),
                  if (saved)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: const Color(0xe6070c09),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Icon(Icons.check, size: 14, color: green),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              str(meta, 'name'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text(13, color: active ? white : const Color(0xffcdd8cd)),
            ),
            if (showEpisode &&
                str(meta, 'type') == 'series' &&
                progress.videoId.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                progress.episodeLabel,
                key: ValueKey('poster-episode:${str(meta, "id")}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text(11, color: muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A titled horizontal row of posters, with arrow buttons for mouse users.
class Shelf extends StatefulWidget {
  const Shelf({
    super.key,
    required this.title,
    required this.items,
    required this.onOpen,
    this.filter = true,
    this.wheel = false,
    this.continueWatching = false,
  });
  final String title;
  final List<Meta> items;
  final void Function(Meta) onOpen;
  final bool filter, continueWatching;

  /// Lets a vertical mouse wheel scroll the row sideways, handing back to the page at either end.
  final bool wheel;

  @override
  State<Shelf> createState() => _ShelfState();
}

class _ShelfState extends State<Shelf> {
  final _scroll = ScrollController();
  bool _hover = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _page(int direction) {
    final width = _scroll.position.viewportDimension * .8;
    _scroll.animateTo(
      (_scroll.offset + direction * width).clamp(
        0,
        _scroll.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  void _wheel(PointerSignalEvent e) {
    if (!widget.wheel ||
        e is! PointerScrollEvent ||
        e.scrollDelta.dy == 0 ||
        !_scroll.hasClients) {
      return;
    }
    final p = _scroll.position;
    final target = (p.pixels + e.scrollDelta.dy * 2).clamp(
      p.minScrollExtent,
      p.maxScrollExtent,
    );
    if (target == p.pixels) return;
    GestureBinding.instance.pointerSignalResolver.register(
      e,
      (_) => _scroll.jumpTo(target),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items =
        (widget.filter ? Catalog.instance.playable(widget.items) : widget.items)
            .take(20)
            .toList();
    if (items.isEmpty) return const SizedBox.shrink();
    final width = posterWidth(context);
    final height = width * 1.48 + 34 + (widget.continueWatching ? 20 : 0);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              gutter(context),
              10,
              gutter(context),
              4,
            ),
            child: Text(widget.title, style: text(20, weight: FontWeight.w500)),
          ),
          SizedBox(
            height: height + 36,
            child: Stack(
              children: [
                Listener(
                  onPointerSignal: _wheel,
                  child: ListView.separated(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    padding: EdgeInsets.fromLTRB(
                      gutter(context),
                      16,
                      gutter(context),
                      18,
                    ),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 14),
                    itemBuilder: (context, i) => PosterCard(
                      meta: items[i],
                      width: width,
                      showEpisode: widget.continueWatching,
                      onOpen: () => widget.onOpen(items[i]),
                    ),
                  ),
                ),
                if (_hover) ...[
                  Positioned(
                    left: 6,
                    top: 16,
                    bottom: 52,
                    child: _Arrow(
                      icon: Icons.chevron_left,
                      onTap: () => _page(-1),
                    ),
                  ),
                  Positioned(
                    right: 6,
                    top: 16,
                    bottom: 52,
                    child: _Arrow(
                      icon: Icons.chevron_right,
                      onTap: () => _page(1),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Center(
    child: ExcludeFocus(
      child: Lift(
        onTap: onTap,
        builder: (context, active) => Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: active ? white : const Color(0xd9121c15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: active ? ink : white),
        ),
      ),
    ),
  );
}

/// Width of the collapsed desktop side rail; the TV keeps its top bar.
double get railWidth => desktop ? 76 : 0;

double gutter(BuildContext context) =>
    railWidth + (MediaQuery.sizeOf(context).width < 900 ? 28 : 48);

double posterWidth(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  return w < 1100
      ? 116
      : w < 1500
      ? 150
      : 170;
}

class PosterGrid extends StatelessWidget {
  const PosterGrid({super.key, required this.items, required this.onOpen});
  final List<Meta> items;
  final void Function(Meta) onOpen;
  @override
  Widget build(BuildContext context) {
    final width = posterWidth(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: gutter(context), vertical: 12),
      child: Wrap(
        spacing: 14,
        runSpacing: 26,
        children: [
          for (final m in items)
            PosterCard(meta: m, width: width, onOpen: () => onOpen(m)),
        ],
      ),
    );
  }
}
