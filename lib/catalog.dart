import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'net.dart';
import 'store.dart';

const cinemeta = 'https://v3-cinemeta.strem.io';
const _tmdb = 'https://tmdb.elfhosted.com';
const _streaming = 'https://7a82163c306e-stremio-netflix-catalog-addon.baby-beamup.club';
const _mdb = 'https://mdblist.com/lists/linaspurinis/';

const movieGenres = ['Action', 'Comedy', 'Thriller', 'Sci-Fi', 'Horror', 'Animation', 'Drama', 'Romance', 'Crime', 'Family', 'Adventure', 'Mystery'];
const seriesGenres = ['Drama', 'Comedy', 'Crime', 'Sci-Fi', 'Animation', 'Mystery', 'Action', 'Fantasy', 'Thriller', 'Documentary', 'Reality-TV', 'Family'];
const services = [
  ['nfx', 'Netflix'],
  ['amp', 'Prime Video'],
  ['dnp', 'Disney+'],
  ['hbm', 'HBO Max'],
  ['atp', 'Apple TV+'],
];
const _mdbLists = {'movie/x-week': 'top-watched-movies-of-the-week', 'series/x-week': 'most-popular-shows-top-50', 'movie/x-fresh': 'latest-certified-fresh-releases', 'series/x-fresh': 'best-new-shows'};

/// Catalog cache, refresh and recommendation ranking. Mirrors the Fire TV app.
class Catalog extends ChangeNotifier {
  static final instance = Catalog();
  final Map<String, List<Meta>> _catalogs = {};
  late Directory _dir;
  bool _refreshing = false;
  int _version = 0;
  Store get _store => Store.instance;

  int get year => DateTime.now().year;
  int get day => DateTime.now().difference(DateTime(DateTime.now().year)).inDays + year * 1000;

  Future<void> open() async {
    _dir = await getApplicationSupportDirectory();
    final bundled = <String, String>{};
    for (final type in ['movie', 'series']) {
      try {
        bundled['$type/top'] = await rootBundle.loadString('assets/${type == 'movie' ? 'movies' : 'series'}.json');
      } catch (_) {}
    }
    final dir = _dir.path, wanted = specs();
    _catalogs.addAll(await Isolate.run(() => _loadCatalogs(dir, wanted, bundled)));
    _version++;
    _shownDay = day;
  }

  int _shownDay = 0;

  /// Refetches lists past their age and, once the date changes, redraws so the daily shuffle shows.
  Future<void> keepFresh() async {
    await refresh();
    if (_shownDay == day) return;
    _shownDay = day;
    notifyListeners();
  }

  List<String> specs() => [
    for (final type in ['movie', 'series']) ...[
      '$type/top',
      '$type/imdbRating',
      '$type/year/genre=$year',
      for (final g in type == 'movie' ? movieGenres : seriesGenres) '$type/top/genre=$g',
      '$type/x-trending',
      '$type/x-week',
      '$type/x-fresh',
      for (final s in services) '$type/x-${s[0]}',
    ],
  ];

  File _file(String spec) => _catalogFile(_dir.path, spec);

  List<Meta> _metas(dynamic list) => _metaList(list);

  List<Meta> catalog(String spec) => _catalogs[spec] ?? const [];

  Future<void> refresh({bool force = false}) async {
    if (_refreshing) return;
    final now = DateTime.now();
    final due = specs().where((spec) {
      final f = _file(spec);
      final maxAge = spec.endsWith('/top') || spec.endsWith('/x-trending')
          ? 6
          : spec.contains('/x-')
          ? 12
          : 20;
      return force || !f.existsSync() || now.difference(f.lastModifiedSync()).inHours >= maxAge;
    }).toList();
    if (due.isEmpty) return;
    _refreshing = true;
    var changed = false;
    final queue = List.of(due);
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final spec = queue.removeAt(0);
        try {
          final metas = _lean(await _fetch(spec));
          if (metas.isEmpty) continue;
          await _file(spec).writeAsString(jsonEncode({'metas': metas}));
          _catalogs[spec] = metas;
          changed = true;
        } catch (e) {
          debugPrint('Catalog refresh failed: $spec $e');
        }
      }
    }

    await Future.wait(List.generate(3, (_) => worker()));
    _refreshing = false;
    if (changed) {
      _version++;
      notifyListeners();
    }
  }

  Future<List<Meta>> _fetch(String spec) async {
    if (!spec.contains('/x-')) return _metas((await getJson('$cinemeta/catalog/$spec.json'))['metas']);
    final type = spec.substring(0, spec.indexOf('/'));
    final key = spec.substring(spec.indexOf('/x-') + 3);
    final out = <Meta>[];
    final list = _mdbLists[spec];
    if (list != null) {
      final items = await getJson('$_mdb$list/json');
      for (final item in items is List ? items : const []) {
        if (out.length >= 30) break;
        final id = item is Map ? '${item['imdb_id']}' : '';
        if (!id.startsWith('tt')) continue;
        final m = await cachedMeta(type, id);
        if (m != null) out.add(m);
      }
      return out;
    }
    final url = key == 'trending' ? '$_tmdb/catalog/$type/tmdb.trending/genre=Day.json' : '$_streaming/catalog/$type/$key.json';
    for (final raw in _metas((await getJson(url))['metas'])) {
      var id = str(raw, 'id');
      if (!id.startsWith('tt')) id = str(raw, 'imdb_id');
      if (!id.startsWith('tt')) id = RegExp(r'tt\d+').firstMatch(jsonEncode(raw['links'] ?? ''))?.group(0) ?? '';
      if (!id.startsWith('tt')) continue;
      final m = slim(raw, type, id);
      if (type == 'movie' && !m.containsKey('released')) {
        final full = await cachedMeta(type, id);
        if (full != null && full.containsKey('released')) m['released'] = full['released'];
      }
      out.add(m);
    }
    return out;
  }

  Future<Meta?> cachedMeta(String type, String id) async {
    final cached = _store.recalled(id);
    if (cached != null && (type == 'series' || cached.containsKey('released'))) return cached;
    try {
      final m = (await getJson('$cinemeta/meta/$type/$id.json'))['meta'];
      if (m is! Map || '${m['name'] ?? ''}'.isEmpty) return null;
      final s = slim(Map<String, dynamic>.from(m), type, id);
      _store.remember(s);
      return s;
    } catch (_) {
      return null;
    }
  }

  static Meta slim(Meta m, String type, String id) {
    final o = <String, dynamic>{'id': id, 'type': type};
    for (final k in ['name', 'poster', 'background', 'logo', 'description', 'releaseInfo', 'released', 'year', 'imdbRating', 'runtime']) {
      if (str(m, k).isNotEmpty && str(m, k) != 'null') o[k] = str(m, k);
    }
    final g = genres(m);
    if (g.isNotEmpty) o['genres'] = g;
    if (!o.containsKey('releaseInfo') && o.containsKey('year')) o['releaseInfo'] = o['year'];
    return o;
  }

  // Ranking ------------------------------------------------------------------

  int _indexed = -1;
  final Set<String> _known = {}, _streamingIds = {};
  final Map<String, DateTime> _released = {};

  void _index() {
    if (_indexed == _version) return;
    _known.clear();
    _streamingIds.clear();
    _released.clear();
    _catalogs.forEach((key, list) {
      final service = services.any((s) => key.endsWith('/x-${s[0]}'));
      for (final m in list) {
        final id = str(m, 'id');
        if (!key.contains('/year/')) _known.add(id);
        if (service) _streamingIds.add(id);
        final r = DateTime.tryParse(str(m, 'released'));
        if (r != null) _released.putIfAbsent(id, () => r);
      }
    });
    _indexed = _version;
  }

  List<Meta> pool(String? type) {
    final map = <String, Meta>{};
    final keys = _catalogs.keys.toList()..sort();
    for (final t in type == null ? ['movie', 'series'] : [type]) {
      for (final key in keys) {
        if (!key.startsWith('$t/')) continue;
        for (final m in _catalogs[key]!) {
          map.putIfAbsent(str(m, 'id'), () => m);
        }
      }
    }
    return map.values.toList();
  }

  List<Meta> all() => pool(null);

  static List<Meta> mix(List<Meta> a, List<Meta> b) {
    final map = <String, Meta>{};
    for (var i = 0; i < (a.length > b.length ? a.length : b.length); i++) {
      if (i < a.length) map.putIfAbsent(str(a[i], 'id'), () => a[i]);
      if (i < b.length) map.putIfAbsent(str(b[i], 'id'), () => b[i]);
    }
    return map.values.toList();
  }

  static double rating(Meta m) => double.tryParse(str(m, 'imdbRating')) ?? 0;
  static int released(Meta m) => int.tryParse(str(m, 'releaseInfo').padRight(4).substring(0, 4)) ?? int.tryParse(str(m, 'year')) ?? 0;

  int _popularAt = -1;
  final Map<String, double> _popular = {};

  double popularity(Meta m) {
    if (_popularAt != _version) {
      _popular.clear();
      for (final type in ['movie', 'series']) {
        for (final spec in ['/top', '/x-trending', '/x-week']) {
          final top = catalog('$type$spec');
          for (var i = 0; i < top.length; i++) {
            final key = '$type:${str(top[i], 'id')}', v = 1 - i / top.length;
            if (v > (_popular[key] ?? -1)) _popular[key] = v;
          }
        }
      }
      _popularAt = _version;
    }
    return _popular['${str(m, 'type')}:${str(m, 'id')}'] ?? 0;
  }

  double jitter(String key) => ('$key$day'.hashCode & 0xffff) / 65535.0;

  bool known(Meta m) {
    _index();
    return _known.contains(str(m, 'id'));
  }

  bool theatrical(Meta m) {
    if (str(m, 'type') != 'movie') return false;
    _index();
    final id = str(m, 'id');
    if (_store.now() - _store.getInt('nostreams:$id') < 3 * 86400000) return true;
    if (_streamingIds.contains(id)) return false;
    final at = _released[id] ?? DateTime.tryParse(str(m, 'released'));
    return at != null && DateTime.now().difference(at).inDays < 45;
  }

  List<Meta> playable(List<Meta> list) => list.where((m) => !theatrical(m)).toList();
  static List<Meta> decent(List<Meta> list) => list.where((m) => rating(m) == 0 || rating(m) >= 6.3).toList();

  List<Meta> ranked(List<Meta> pool, String salt, [double floor = 7.0]) {
    final peak = _store.peakGenre();
    final value = <String, double>{};
    final out = <Meta>[];
    for (final m in pool) {
      if (_store.saved(m) || _store.watched(m) || rating(m) < floor || !known(m) || theatrical(m)) continue;
      final id = str(m, 'id');
      value[id] = (rating(m) - 7) * 1.1 + popularity(m) * 1.3 + (released(m) >= year - 1 ? 0.5 : 0) + (peak > 0 ? 2.5 * (_store.affinity(m) / peak).clamp(0, 1) : 0) + jitter(id + salt) * 0.6;
      out.add(m);
    }
    out.sort((a, b) => value[str(b, 'id')]!.compareTo(value[str(a, 'id')]!));
    return out;
  }

  List<Meta> similar(Meta meta, [int count = 20]) {
    final id = str(meta, 'id'), want = genres(meta).toSet();
    if (want.isEmpty) return const [];
    final value = <String, double>{};
    final out = <Meta>[];
    for (final m in pool(str(meta, 'type'))) {
      final other = str(m, 'id');
      if (other == id || rating(m) < 6.5 || theatrical(m)) continue;
      final shared = genres(m).where(want.contains).length;
      if (shared == 0) continue;
      value[other] = shared / want.length * 3 + (rating(m) - 7) + popularity(m) + jitter(other + id) * 0.4;
      out.add(m);
    }
    out.sort((a, b) => value[str(b, 'id')]!.compareTo(value[str(a, 'id')]!));
    return out.take(count).toList();
  }

  static List<Meta> wide(List<Meta> list, Set<String> skip, int count) => list.where((m) => str(m, 'background').isNotEmpty && !skip.contains(str(m, 'id'))).take(count).toList();

  List<Meta> heroes(String? type) {
    final home = mix(wide(ranked(pool('movie'), 'heroHome', 7.3), {}, 3), wide(ranked(pool('series'), 'heroHome', 7.3), {}, 2));
    if (type == null) return home;
    return wide(ranked(pool(type), 'hero$type', 7.3), home.map((m) => str(m, 'id')).toSet(), 5);
  }

  List<String> genreRows(String? type, int count) {
    final options = type == 'series' ? seriesGenres : movieGenres;
    final liked = options.where((g) => _store.getInt('genre:$g') > 0).toList()..sort((a, b) => _store.getInt('genre:$b').compareTo(_store.getInt('genre:$a')));
    final rest = options.where((g) => _store.getInt('genre:$g') == 0).toList()..sort((a, b) => jitter(a).compareTo(jitter(b)));
    final rows = liked.take(2).toList();
    for (final g in rest) {
      if (rows.length < count) rows.add(g);
    }
    return rows;
  }

  List<Meta> library() {
    final everything = {for (final m in all()) str(m, 'id'): m};
    return [
      for (final id in _store.savedIds())
        if (everything[id] ?? _store.recalled(id) case final Meta m) m,
    ];
  }

  List<Meta> continueWatching() {
    final recent = all().where(_store.watched).toList();
    for (final key in _store.keys()) {
      if (!key.startsWith('opened:')) continue;
      final id = key.substring(7);
      if (recent.any((m) => str(m, 'id') == id)) continue;
      final m = _store.recalled(id);
      if (m != null) recent.add(m);
    }
    recent.sort((a, b) => _store.getInt('opened:${b['id']}').compareTo(_store.getInt('opened:${a['id']}')));
    return recent;
  }
}

File _catalogFile(String dir, String spec) => File('$dir/catalog-${spec.replaceAll(RegExp('[^A-Za-z0-9]+'), '_')}.json');

List<Meta> _metaList(dynamic list) => list is List ? list.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).where((m) => str(m, 'id').isNotEmpty).toList() : [];

/// Episode lists, links and trailers dwarf what browsing needs; the details page fetches them fresh.
const _bulk = ['videos', 'links', 'trailers', 'trailerStreams', 'popularities', 'popularity', 'behaviorHints', 'credits_cast', 'credits_crew', 'slug', 'awards'];

List<Meta> _lean(List<Meta> metas) {
  for (final m in metas) {
    for (final k in _bulk) {
      m.remove(k);
    }
    final cast = m['cast'];
    if (cast is List && cast.length > 4) m['cast'] = cast.take(4).toList();
  }
  return metas;
}

/// Runs on a background isolate so the splash keeps animating.
Map<String, List<Meta>> _loadCatalogs(String dir, List<String> specs, Map<String, String> bundled) {
  final out = <String, List<Meta>>{};
  bundled.forEach((spec, raw) {
    try {
      out[spec] = _lean(_metaList(jsonDecode(raw)['metas']));
    } catch (_) {}
  });
  for (final spec in specs) {
    final f = _catalogFile(dir, spec);
    if (!f.existsSync()) continue;
    try {
      final list = _lean(_metaList(jsonDecode(f.readAsStringSync())['metas']));
      if (list.isEmpty) continue;
      out[spec] = list;
      if (f.lengthSync() > 96 * 1024) {
        final modified = f.lastModifiedSync();
        f.writeAsStringSync(jsonEncode({'metas': list}));
        f.setLastModifiedSync(modified);
      }
    } catch (_) {}
  }
  return out;
}
