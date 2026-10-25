import 'package:flutter/material.dart';

import 'browse.dart';
import 'catalog.dart';
import 'net.dart';
import 'routes.dart';
import 'remote_navigation.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets.dart';
import 'watch_progress.dart';

class DetailPage extends StatefulWidget {
  const DetailPage({super.key, required this.meta, this.resumeVideo});
  final Meta meta;
  final String? resumeVideo;
  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  late Meta meta = {
    ...?Store.instance.recalled(str(widget.meta, 'id')),
    ...widget.meta,
  };
  late String? resumeVideo = widget.resumeVideo;
  bool get episodeView => series && (resumeVideo?.isNotEmpty ?? false);
  WatchProgress get progress =>
      Store.instance.progress(meta, video: resumeVideo);
  bool loading = true, failed = false;
  int? season;
  bool get series => str(meta, 'type') == 'series';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      final full = Map<String, dynamic>.from(
        (await getJson(
          '$cinemeta/meta/${Uri.encodeComponent(str(meta, 'type'))}/${Uri.encodeComponent(str(meta, 'id'))}.json',
        ))['meta'],
      );
      if (series) await _summaries(full);
      if (!mounted) return;
      setState(() {
        meta = {...widget.meta, ...full};
        loading = false;
        final seasons = _seasons();
        season = episodeView && seasons.contains(progress.season)
            ? progress.season
            : seasons.isEmpty
            ? null
            : seasons.first;
        Store.instance.remember(meta);
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          failed = true;
        });
      }
    }
  }

  /// Cinemeta often lacks episode synopses; TVmaze fills the gaps.
  Future<void> _summaries(Meta show) async {
    final videos = show['videos'];
    if (videos is! List ||
        !videos.any(
          (v) =>
              v is Map &&
              (v['season'] ?? 0) > 0 &&
              '${v['overview'] ?? ''}'.isEmpty,
        )) {
      return;
    }
    try {
      final found = await getJson(
        'https://api.tvmaze.com/lookup/shows?imdb=${Uri.encodeComponent(str(show, 'id'))}',
      );
      final episodes = await getJson(
        'https://api.tvmaze.com/shows/${found['id']}/episodes',
      );
      final text = <String, String>{};
      for (final e in episodes is List ? episodes : const []) {
        final summary = '${e['summary'] ?? ''}'
            .replaceAll(RegExp(r'<[^>]+>'), '')
            .replaceAll('&amp;', '&')
            .replaceAll('&quot;', '"')
            .replaceAll('&#39;', "'")
            .trim();
        if (summary.isNotEmpty && summary != 'null') {
          text['${e['season']}:${e['number']}'] = summary;
        }
      }
      for (final v in videos) {
        if (v is Map && '${v['overview'] ?? ''}'.isEmpty) {
          final s = text['${v['season']}:${v['episode']}'];
          if (s != null) v['overview'] = s;
        }
      }
    } catch (_) {}
  }

  bool _aired(Map v) {
    final r = DateTime.tryParse('${v['released'] ?? v['firstAired'] ?? ''}');
    return r == null || !r.isAfter(DateTime.now());
  }

  List<Map> _videos() =>
      (meta['videos'] is List ? meta['videos'] as List : const [])
          .whereType<Map>()
          .where((v) => '${v['id'] ?? ''}'.isNotEmpty && _aired(v))
          .toList();

  List<int> _seasons() {
    final s =
        _videos()
            .map((v) => (v['season'] as num?)?.toInt() ?? 0)
            .where((s) => s > 0)
            .toSet()
            .toList()
          ..sort();
    return s.isEmpty && _videos().isNotEmpty ? [0] : s;
  }

  String? _firstEpisode() {
    Map? best;
    for (final v in _videos()) {
      final s = (v['season'] as num?)?.toInt() ?? 0,
          bs = (best?['season'] as num?)?.toInt() ?? 0;
      if (best == null ||
          (s > 0 && (bs == 0 || s < bs)) ||
          (s == bs &&
              ((v['episode'] as num?) ?? 0) <
                  ((best['episode'] as num?) ?? 0))) {
        best = v;
      }
    }
    return best == null ? null : '${best['id']}';
  }

  Future<void> _playVideo(String video) async {
    await play(context, meta, video);
    if (!mounted) return;
    setState(() {
      if (episodeView) {
        resumeVideo = Store.instance.getString(
          'video:${str(meta, "id")}',
          video,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final saved = Store.instance.saved(meta);
    final watching = progress;
    return Screen(
      child: RemoteDetailList(
        hero: HeroFrame(
          meta: episodeView ? watching.heroFor(meta) : meta,
          details: true,
          eyebrow: episodeView ? str(meta, "name") : null,
          infoOverride: episodeView ? watching.episodeCode : null,
          descriptionLines: episodeView ? 3 : null,
          actions: [
            Pill(
              icon: Icons.play_arrow_rounded,
              label: episodeView || watching.positionMs > 0 ? 'Resume' : 'Play',
              primary: true,
              autofocus: true,
              onTap: () {
                if (episodeView) {
                  _playVideo(watching.videoId);
                } else if (!series) {
                  _playVideo(str(meta, 'id'));
                } else {
                  final first = _firstEpisode();
                  if (first != null) _playVideo(first);
                }
              },
            ),
            const SizedBox(width: 14),
            Pill(
              icon: saved ? Icons.check_rounded : Icons.add_rounded,
              label: saved ? 'In My List' : 'My List',
              onTap: () => setState(() => Store.instance.toggleSaved(meta)),
            ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!series &&
                meta['cast'] is List &&
                (meta['cast'] as List).isNotEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  gutter(context),
                  0,
                  gutter(context),
                  24,
                ),
                child: Text(
                  'Starring  ${(meta['cast'] as List).take(4).join(' · ')}',
                  style: text(13, color: muted),
                ),
              ),
            if (series) ..._episodes(context),
            if (Catalog.instance.similar(meta) case final more
                when more.isNotEmpty) ...[
              SizedBox(height: series ? 44 : 12),
              Shelf(
                title: 'More Like This',
                items: more,
                filter: false,
                wheel: true,
                onOpen: (m) => openDetail(context, m),
              ),
            ],
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  List<Widget> _episodes(BuildContext context) {
    final pad = EdgeInsets.symmetric(horizontal: gutter(context));
    if (loading) {
      return [
        Padding(
          padding: pad,
          child: Text('Loading…', style: text(14, color: muted)),
        ),
      ];
    }
    if (failed || _seasons().isEmpty) {
      return [
        Padding(
          padding: pad,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Pill(label: 'Retry episodes', primary: true, onTap: _load),
          ),
        ),
      ];
    }
    final episodes =
        _videos()
            .where((v) => ((v['season'] as num?)?.toInt() ?? 0) == season)
            .toList()
          ..sort(
            (a, b) => ((a['episode'] as num?) ?? 0).compareTo(
              (b['episode'] as num?) ?? 0,
            ),
          );
    final width = MediaQuery.sizeOf(context).width;
    final columns = width < 1100
        ? 3
        : width < 1700
        ? 4
        : 5;
    final cardWidth =
        (width - gutter(context) * 2 - (columns - 1) * 18) / columns;
    return [
      SizedBox(
        height: 66,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.fromLTRB(gutter(context), 6, gutter(context), 10),
          children: [
            for (final s in _seasons())
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Pill(
                  label: 'Season $s',
                  primary: s == season,
                  height: 42,
                  onTap: () => setState(() => season = s),
                ),
              ),
          ],
        ),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(gutter(context), 14, gutter(context), 0),
        child: episodes.isEmpty
            ? Text(
                'No released episodes in this season.',
                style: text(14, color: muted),
              )
            : Wrap(
                spacing: 18,
                runSpacing: 26,
                children: [
                  for (final v in episodes)
                    _EpisodeCard(
                      show: meta,
                      video: v,
                      width: cardWidth,
                      onPlay: () => _playVideo('${v['id']}'),
                    ),
                ],
              ),
      ),
    ];
  }
}

class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({
    required this.show,
    required this.video,
    required this.width,
    required this.onPlay,
  });
  final VoidCallback onPlay;
  final Meta show;
  final Map video;
  final double width;

  @override
  Widget build(BuildContext context) {
    var thumb = '${video['thumbnail'] ?? ''}';
    if (!thumb.startsWith('https://')) thumb = str(show, 'background');
    final number = video['episode'] ?? '';
    final name = '${video['name'] ?? video['title'] ?? 'Episode $number'}';
    final about = '${video['overview'] ?? video['description'] ?? ''}';
    final progress = Store.instance.getInt('position:${video['id']}'),
        length = Store.instance.getInt('duration:${video['id']}');
    return SizedBox(
      width: width,
      child: Lift(
        scale: 1.03,
        glow: true,
        onTap: onPlay,
        builder: (context, active) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Artwork(thumb, width: width),
                  if (length > 0 && progress > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(7),
                        ),
                        child: LinearProgressIndicator(
                          value: (progress / length).clamp(0, 1),
                          minHeight: 3,
                          color: green,
                          backgroundColor: const Color(0x55070c09),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '$number.  $name',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text(
                14,
                weight: FontWeight.w500,
                color: active ? green : white,
              ),
            ),
            if (about.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                about,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text(12, color: muted, height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
