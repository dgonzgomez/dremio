import 'package:dremio/detail.dart';
import 'package:dremio/store.dart';
import 'package:dremio/watch_progress.dart';
import 'package:dremio/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final show = <String, dynamic>{
  'id': 'tt1234567',
  'type': 'series',
  'name': 'Example Show',
  'background': '',
  'videos': [
    {
      'id': 'tt1234567:1:1',
      'season': 1,
      'episode': 1,
      'name': 'The Beginning',
      'overview': 'The first episode.',
    },
    {
      'id': 'tt1234567:1:4',
      'season': 1,
      'episode': 4,
      'name': 'The Fourth Signal',
      'overview': 'An unexpected message changes the mission.',
      'thumbnail': '',
    },
  ],
};

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.open();
  });

  test(
    'series progress uses episode four even when the catalog lacks episodes',
    () {
      final store = Store.instance;
      store.recordPlayback(show, 'tt1234567:1:4');
      store.saveProgress('tt1234567:1:4', 120000, 480000);
      final progress = store.progress({
        'id': 'tt1234567',
        'type': 'series',
        'name': 'Example Show',
      });
      expect(progress.videoId, 'tt1234567:1:4');
      expect(progress.episodeLabel, 'S1 · E4 · The Fourth Signal');
      expect(progress.fraction, .25);
      expect(progress.heroFor(show)['name'], 'The Fourth Signal');
      expect(
        progress.heroFor(show)['description'],
        'An unexpected message changes the mission.',
      );
    },
  );

  test(
    'legacy episode IDs still identify the season and episode without metadata',
    () {
      const progress = WatchProgress(
        videoId: 'tt1234567:2:4',
        positionMs: 15000,
        durationMs: 60000,
      );
      expect(progress.episodeLabel, 'S2 · E4');
      expect(progress.heroFor(show)['name'], 'Episode 4');
      expect(progress.fraction, .25);
    },
  );

  test('movie progress uses the movie ID and clamps the poster bar', () {
    Store.instance.saveProgress('tt7654321', 60000, 120000);
    final progress = Store.instance.progress({
      'id': 'tt7654321',
      'type': 'movie',
    });
    expect(progress.videoId, 'tt7654321');
    expect(progress.fraction, .5);
    expect(
      const WatchProgress(
        videoId: 'x',
        positionMs: 300,
        durationMs: 100,
      ).fraction,
      1,
    );
    expect(
      const WatchProgress(
        videoId: 'x',
        positionMs: 300,
        durationMs: 0,
      ).hasProgress,
      isFalse,
    );
  });

  testWidgets(
    'series poster shows episode subtitle and live progress; movies also show a bar',
    (tester) async {
      final store = Store.instance;
      store.recordPlayback(show, 'tt1234567:1:4');
      store.saveProgress('tt1234567:1:4', 120000, 480000);
      store.saveProgress('tt7654321', 60000, 120000);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PosterCard(
                  meta: show,
                  width: 116,
                  showEpisode: true,
                  onOpen: () {},
                ),
                PosterCard(
                  meta: const {
                    'id': 'tt7654321',
                    'type': 'movie',
                    'name': 'Example Movie',
                  },
                  width: 116,
                  onOpen: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('S1 · E4 · The Fourth Signal'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const ValueKey('poster-progress:tt1234567')),
            )
            .value,
        .25,
      );
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const ValueKey('poster-progress:tt7654321')),
            )
            .value,
        .5,
      );
      store.saveProgress('tt1234567:1:4', 240000, 480000);
      await tester.pump();
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const ValueKey('poster-progress:tt1234567')),
            )
            .value,
        .5,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('resume entry opens an episode-focused hero, not episode one', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Store.instance.recordPlayback(show, 'tt1234567:1:4');
    Store.instance.saveProgress('tt1234567:1:4', 120000, 480000);
    await tester.pumpWidget(
      MaterialApp(
        home: DetailPage(meta: show, resumeVideo: 'tt1234567:1:4'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('The Fourth Signal'), findsOneWidget);
    expect(
      find.text('An unexpected message changes the mission.'),
      findsOneWidget,
    );
    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('The Beginning'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
