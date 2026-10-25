import 'package:dremio/remote_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 230));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  testWidgets('deep shelf navigation returns through every row to the hero', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final hero = FocusNode(debugLabel: 'Hero play');
    final cards = List.generate(14, (i) => FocusNode(debugLabel: 'Shelf $i'));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RemoteBrowseList(
            heroExtent: 250,
            shelfExtent: 210,
            shelfExtras: const [20],
            hero: SizedBox(
              height: 250,
              child: Center(
                child: Focus(
                  focusNode: hero,
                  autofocus: true,
                  child: const Text('Hero'),
                ),
              ),
            ),
            shelves: List.generate(
              14,
              (i) => Center(
                child: Focus(focusNode: cards[i], child: Text('Shelf $i')),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(hero.hasPrimaryFocus, isTrue);
    for (var i = 0; i < 11; i++) {
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(
        cards[i].hasPrimaryFocus,
        isTrue,
        reason: 'Down must visit shelf $i even when rebuilt lazily',
      );
    }
    expect(
      hero.context,
      isNotNull,
      reason: 'The hero must remain mounted after scrolling far away',
    );
    for (var i = 9; i >= 0; i--) {
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(
        cards[i].hasPrimaryFocus,
        isTrue,
        reason: 'Up must not skip an unmounted shelf',
      );
    }
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(hero.hasPrimaryFocus, isTrue);
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    expect(scrollable.position.pixels, 0);
    await tester.pumpWidget(const SizedBox());
    hero.dispose();
    for (final card in cards) {
      card.dispose();
    }
  });

  testWidgets('series detail returns through season controls to its hero', (
    tester,
  ) async {
    final play = FocusNode(), season = FocusNode(), episode = FocusNode();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RemoteDetailList(
            hero: SizedBox(
              height: 500,
              child: Center(
                child: Focus(
                  focusNode: play,
                  autofocus: true,
                  child: const Text('Play'),
                ),
              ),
            ),
            body: Column(
              children: [
                SizedBox(
                  height: 80,
                  child: Focus(
                    focusNode: season,
                    child: const Text('Season 1'),
                  ),
                ),
                SizedBox(
                  height: 700,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Focus(
                      focusNode: episode,
                      child: const Text('Episode 1'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(season.hasPrimaryFocus, isTrue);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(episode.hasPrimaryFocus, isTrue);
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(season.hasPrimaryFocus, isTrue);
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(play.hasPrimaryFocus, isTrue);
    expect(
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels,
      0,
    );
    await tester.pumpWidget(const SizedBox());
    for (final node in [play, season, episode]) {
      node.dispose();
    }
  });

  testWidgets(
    'player remote reaches Back and volume, and arrows adjust volume',
    (tester) async {
      final video = FocusNode(),
          back = FocusNode(),
          play = FocusNode(),
          mute = FocusNode(),
          volume = FocusNode(),
          progress = FocusNode();
      var level = 50.0;
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: StatefulBuilder(
              builder: (context, setState) => Focus(
                focusNode: video,
                onKeyEvent: (_, event) => event is KeyDownEvent
                    ? playerControlStep(
                        event.logicalKey,
                        back: back,
                        play: play,
                        progress: progress,
                        video: video,
                        bottom: [play, mute, volume],
                        request: (node) => node.requestFocus(),
                      )
                    : KeyEventResult.ignored,
                child: Column(
                  children: [
                    Focus(focusNode: back, child: const Text('Back')),
                    Focus(focusNode: progress, child: const Text('Progress')),
                    Row(
                      children: [
                        Focus(
                          focusNode: play,
                          autofocus: true,
                          child: const Text('Play'),
                        ),
                        Focus(focusNode: mute, child: const Text('Mute')),
                        SizedBox(
                          width: 130,
                          child: RemoteVolumeKeys(
                            focusNode: volume,
                            value: level,
                            onChanged: (value) => setState(() => level = value),
                            child: Slider(
                              value: level,
                              max: 100,
                              onChanged: (_) {},
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(progress.hasPrimaryFocus, isTrue);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(back.hasPrimaryFocus, isTrue);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(progress.hasPrimaryFocus, isTrue);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(play.hasPrimaryFocus, isTrue);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(
        play.hasPrimaryFocus,
        isTrue,
        reason: 'Down on the bottom row stays there',
      );
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(mute.hasPrimaryFocus, isTrue);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(volume.hasPrimaryFocus, isTrue);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(level, 45);
      expect(volume.hasPrimaryFocus, isTrue);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(
        progress.hasPrimaryFocus,
        isTrue,
        reason: 'The volume control must not swallow Up',
      );
      await tester.pumpWidget(const SizedBox());
      for (final node in [video, back, play, mute, volume, progress]) {
        node.dispose();
      }
    },
  );
  testWidgets('progress bar remote arrows seek in ten-second steps', (
    tester,
  ) async {
    final focus = FocusNode();
    var position = 50000.0;
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: StatefulBuilder(
            builder: (context, setState) => RemoteSliderKeys(
              focusNode: focus,
              value: position,
              maximum: 120000,
              step: 10000,
              onChanged: (value) => setState(() => position = value),
              child: Slider(value: position, max: 120000, onChanged: (_) {}),
            ),
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(position, 40000);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(position, 50000);
    await tester.pumpWidget(const SizedBox());
    focus.dispose();
  });
}
