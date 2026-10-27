import 'package:dremio/browse.dart';
import 'package:dremio/main.dart';
import 'package:dremio/store.dart';
import 'package:dremio/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'shelves clamp horizontal focus and explicitly open the current sidebar tab',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await Store.open();
      currentPage.value = 'Movies';
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Screen(
            child: ListView(
              children: [
                for (var row = 0; row < 2; row++)
                  Shelf(
                    title: 'Row $row',
                    filter: false,
                    items: [
                      for (var i = 0; i < 20; i++)
                        {
                          'id': '$row-$i',
                          'name': 'Movie $row-$i',
                          'type': 'movie',
                        },
                    ],
                    onOpen: (_) {},
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final rows = FocusManager.instance.rootScope.descendants
          .where((n) => n.debugLabel == 'Shelf')
          .toList();
      List<FocusNode> cards(int row) =>
          rows[row].traversalDescendants
              .where(
                (n) =>
                    n.traversalDescendants.isEmpty &&
                    n.canRequestFocus &&
                    !n.skipTraversal,
              )
              .toList()
            ..sort((a, b) => a.rect.left.compareTo(b.rect.left));
      final first = cards(0).first;
      first.requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      for (var i = 0; i < 26; i++) {
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump(const Duration(milliseconds: 20));
        expect(rows[0].hasFocus, isTrue);
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      expect(cards(0).last.hasPrimaryFocus, isTrue);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
      for (var i = 0; i < 18; i++) {
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(first.hasPrimaryFocus, isTrue);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      final movies = FocusManager.instance.rootScope.descendants.firstWhere(
        (n) => n.debugLabel == 'Movies',
      );
      expect(movies.hasPrimaryFocus, isTrue);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 300));
      expect(first.hasPrimaryFocus, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
