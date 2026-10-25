import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'artwork_cache.dart';
import 'browse.dart';
import 'catalog.dart';
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
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        title: 'Dremio',
        size: const Size(1440, 900),
        minimumSize: const Size(960, 620),
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

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
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
