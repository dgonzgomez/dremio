import 'package:dremio/browse.dart';
import 'package:dremio/main.dart';
import 'package:dremio/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Store.open();
    currentPage.value = 'Home';
  });
  FocusNode node(String label) => FocusManager.instance.rootScope.descendants.firstWhere((n) => n.debugLabel == label && n.context != null);
  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
  }

  Future<void> showRail(WidgetTester tester, {double height = 540, TargetPlatform platform = TargetPlatform.android}) async {
    tester.view.physicalSize = Size(960, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: platform),
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 300,
                top: 0,
                child: TextButton(onPressed: () {}, child: const Text('Content outside sidebar')),
              ),
              const Positioned(left: 0, top: 0, bottom: 0, child: SideRail()),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('TV menu fits, logo is decorative, and Up/Down stay inside the sidebar', (tester) async {
    await showRail(tester);
    expect(find.descendant(of: find.byKey(const ValueKey('sidebar-logo')), matching: find.byType(FocusableActionDetector)), findsNothing);
    node('profile').requestFocus();
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(node('profile').hasPrimaryFocus, isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    for (var i = 0; i < 6; i++) {
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump(const Duration(milliseconds: 80));
      expect(node('profile').hasPrimaryFocus, isTrue);
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
    for (final label in ['Search', 'Home', 'Orbit', 'Movies', 'Series', 'Lookback', 'My List', 'Settings']) {
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(node(label).hasPrimaryFocus, isTrue, reason: label);
      expect(node(label).rect.top, greaterThanOrEqualTo(0));
      expect(node(label).rect.bottom, lessThanOrEqualTo(540));
    }
    expect(node('My List').rect.bottom, lessThan(node('Settings').rect.top));
    for (var i = 0; i < 3; i++) {
      await press(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(node('Settings').hasPrimaryFocus, isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    for (var i = 0; i < 6; i++) {
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 80));
      expect(node('Settings').hasPrimaryFocus, isTrue);
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(node('My List').hasPrimaryFocus, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('short TV screens scroll through every decade and still reach Settings', (tester) async {
    await showRail(tester, height: 360);
    node('Lookback').requestFocus();
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(node('1940s').hasPrimaryFocus, isTrue);
    for (final label in ['1950s', '1960s', '1970s', '1980s', '1990s', '2000s', '2010s', 'Settings']) {
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(node(label).hasPrimaryFocus, isTrue, reason: label);
      expect(node(label).rect.top, greaterThanOrEqualTo(0));
      expect(node(label).rect.bottom, lessThanOrEqualTo(360), reason: label);
    }
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(node('Settings').hasPrimaryFocus, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('picking a page hands focus to the page, and coming back lands on the current page', (tester) async {
    await showRail(tester);
    node('Orbit').requestFocus();
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.enter);
    expect(currentPage.value, 'Orbit');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    final content = FocusManager.instance.rootScope.descendants.firstWhere((n) => n.rect.left >= 290 && n.context != null && n.traversalDescendants.isEmpty && !n.skipTraversal);
    expect(content.hasPrimaryFocus, isTrue, reason: 'focus left the rail');
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(node('Orbit').hasPrimaryFocus, isTrue, reason: 'rail highlights the open page');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('desktop logo has no focusable action either', (tester) async {
    await showRail(tester, height: 800, platform: TargetPlatform.windows);
    final logo = find.byKey(const ValueKey('sidebar-logo'));
    expect(find.descendant(of: logo, matching: find.byType(FocusableActionDetector)), findsNothing);
    currentPage.value = 'Movies';
    await tester.pump();
    await tester.tap(logo, warnIfMissed: false);
    await tester.pump();
    expect(currentPage.value, 'Movies');
    await tester.pumpWidget(const SizedBox());
  });
}
