import 'package:window_manager/window_manager.dart';

import 'main.dart';

/// A maximized window only half-enters full screen (the title bar stays), so leave maximized first and restore it afterwards.
class FullScreen {
  static bool _maximizedBefore = false;

  static Future<void> set(bool value) async {
    if (!desktop || value == await windowManager.isFullScreen()) return;
    if (value) {
      _maximizedBefore = await windowManager.isMaximized();
      if (_maximizedBefore) await windowManager.unmaximize();
    } else if (_maximizedBefore) {
      _maximizedBefore = false;
      windowManager.addListener(_MaximizeAfterFullScreen());
    }
    await windowManager.setFullScreen(value);
  }

  static Future<void> toggle() async =>
      set(!await windowManager.isFullScreen());
}

class _MaximizeAfterFullScreen with WindowListener {
  @override
  void onWindowLeaveFullScreen() {
    windowManager.removeListener(this);
    windowManager.maximize();
  }
}
