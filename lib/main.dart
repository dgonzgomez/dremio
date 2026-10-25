import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'artwork_cache.dart';
import 'browse.dart';
import 'catalog.dart';
import 'fullscreen.dart';
import 'net.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets.dart';

final desktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;

Future<void> main() async {
  HttpOverrides.global = PreferIPv4();
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  if (!desktop) {
    PaintingBinding.instance.imageCache.maximumSizeBytes = 48 * 1024 * 1024;
    PaintingBinding.instance.imageCache.maximumSize = 180;
  }
  if (desktop) {
    await windowManager.ensureInitialized();
    final fit = _fitScreen();
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        title: 'Dremio',
        size: fit.size,
        minimumSize: fit.minimum,
        center: true,
        backgroundColor: ink,
        titleBarStyle: Platform.isMacOS
            ? TitleBarStyle.hidden
            : TitleBarStyle.normal,
      ),
      () {},
    );
  }
  final boot = () async {
    await ArtworkCache.open();
    await Store.open();
    await Catalog.instance.open();
  }();
  if (!desktop) {
    const mark = SvgAssetLoader('assets/dremio-mark.svg');
    await svg.cache
        .putIfAbsent(mark.cacheKey(null), () => mark.loadBytes(null))
        .catchError((_) => ByteData(0));
    runApp(Boot(ready: boot));
    await boot;
    Catalog.instance.refresh();
    return;
  }
  await boot;
  runApp(const DremioApp());
  if (desktop) {
    // A hidden window may never get a vsync, so don't wait on the first frame forever.
    await Future.any([
      WidgetsBinding.instance.waitUntilFirstFrameRasterized,
      Future<void>.delayed(const Duration(milliseconds: 800)),
    ]);
    await windowManager.show();
    await windowManager.focus();
  }
  Catalog.instance.refresh();
}

/// Opens at 1440x900 where it fits, otherwise shrinks to the screen (in logical
/// pixels, so display scaling counts), leaving room for the title bar and taskbar.
({Size size, Size minimum}) _fitScreen() {
  final display =
      WidgetsBinding.instance.platformDispatcher.views.first.display;
  final screen = display.size / display.devicePixelRatio;
  if (screen.isEmpty) {
    return (size: const Size(1440, 900), minimum: const Size(960, 620));
  }
  final room = Size(screen.width * .92, screen.height * .85);
  return (
    size: Size(math.min(1440, room.width), math.min(900, room.height)),
    minimum: Size(math.min(960, room.width), math.min(620, room.height)),
  );
}

/// Remembers when the user last touched anything, so background refreshes and hero rotation stay out of the way.
class Activity {
  static int lastInput = 0;
  static bool interacted = false;
  static void touch() {
    lastInput = DateTime.now().millisecondsSinceEpoch;
    interacted = true;
  }

  static bool idleFor(int ms) =>
      DateTime.now().millisecondsSinceEpoch - lastInput > ms;
}

/// Keeps the launch logo hovering until the catalogs are ready, then fades into the app.
class Boot extends StatefulWidget {
  const Boot({super.key, required this.ready});
  final Future<void> ready;
  @override
  State<Boot> createState() => _BootState();
}

class _BootState extends State<Boot> {
  bool done = false;

  @override
  void initState() {
    super.initState();
    widget.ready.whenComplete(() {
      if (mounted) setState(() => done = true);
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 320),
    child: done
        ? const DremioApp()
        : const Directionality(
            textDirection: TextDirection.ltr,
            child: ColoredBox(
              color: ink,
              child: Center(child: HoverLogo()),
            ),
          ),
  );
}

class DremioApp extends StatefulWidget {
  const DremioApp({super.key});
  @override
  State<DremioApp> createState() => _DremioAppState();
}

class _DremioAppState extends State<DremioApp> {
  bool _onKey(KeyEvent event) {
    Activity.touch();
    return false;
  }

  /// Runs before the focused widget sees the key, so Alt+Enter never also presses the focused button.
  KeyEventResult _fullScreenKey(KeyEvent event) {
    final enter =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!enter) return KeyEventResult.ignored;
    if (event is KeyDownEvent && HardwareKeyboard.instance.isAltPressed) {
      _swallowEnter = true;
      FullScreen.toggle();
      return KeyEventResult.handled;
    }
    if (!_swallowEnter) return KeyEventResult.ignored;
    if (event is KeyUpEvent) _swallowEnter = false;
    return KeyEventResult.handled;
  }

  bool _swallowEnter = false;

  /// The TV keeps the app alive for days, so recheck the catalog on resume and hourly while idle.
  /// Clearing `interacted` lets Home redraw with the new rows; it only does so before the next input.
  late final AppLifecycleListener _lifecycle;
  late final Timer _freshTimer;

  void _freshen() {
    Activity.interacted = false;
    Catalog.instance.keepFresh();
  }

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _freshen);
    _freshTimer = Timer.periodic(const Duration(hours: 1), (_) {
      if (Activity.idleFor(10 * 60 * 1000)) _freshen();
    });
    HardwareKeyboard.instance.addHandler(_onKey);
    if (desktop) FocusManager.instance.addEarlyKeyEventHandler(_fullScreenKey);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _freshTimer.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
    if (desktop) {
      FocusManager.instance.removeEarlyKeyEventHandler(_fullScreenKey);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => Activity.touch(),
      onPointerSignal: (_) => Activity.touch(),
      child: MaterialApp(
        title: 'Dremio',
        debugShowCheckedModeBanner: false,
        theme: dremioTheme(),
        navigatorKey: navigatorKey,
        shortcuts: {
          ...WidgetsApp.defaultShortcuts,
          // Android turns the remote's Back into a route pop on key-up, so a key-down shortcut there would pop twice.
          if (desktop) ...{
            const SingleActivator(LogicalKeyboardKey.escape):
                const _BackIntent(),
            const SingleActivator(LogicalKeyboardKey.goBack):
                const _BackIntent(),
            const SingleActivator(LogicalKeyboardKey.browserBack):
                const _BackIntent(),
            const SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true):
                const _BackIntent(),
          },
        },
        actions: {
          ...WidgetsApp.defaultActions,
          _BackIntent: CallbackAction<_BackIntent>(onInvoke: (_) => goBack()),
        },
        home: const Shell(),
      ),
    );
  }
}

class _BackIntent extends Intent {
  const _BackIntent();
}

final navigatorKey = GlobalKey<NavigatorState>();
final currentPage = ValueNotifier<String>('Home');

void goBack() {
  final nav = navigatorKey.currentState;
  if (nav == null) return;
  if (nav.canPop()) {
    nav.maybePop();
  } else if (currentPage.value != 'Home') {
    currentPage.value = 'Home';
  }
}

Route<T> fade<T>(Widget page) => PageRouteBuilder<T>(
  pageBuilder: (_, _, _) => page,
  transitionDuration: const Duration(milliseconds: 220),
  reverseTransitionDuration: const Duration(milliseconds: 180),
  transitionsBuilder: (_, animation, _, child) =>
      FadeTransition(opacity: animation, child: child),
);
