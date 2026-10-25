import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';

import 'watch_progress.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef Meta = Map<String, dynamic>;

/// Local library and taste profile. Keys match the Fire TV app.
class Store {
  Store._(this._prefs);
  final SharedPreferences _prefs;
  static late Store instance;
  static const _secure = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );
  String _connection = '';
  final playbackChanges = ValueNotifier<int>(0);
  final _metaCache = <String, Meta>{};

  static Future<void> open() async {
    instance = Store._(await SharedPreferences.getInstance());
    try {
      instance._connection = await _secure.read(key: 'debridio') ?? '';
    } catch (_) {}
  }

  int now() => DateTime.now().millisecondsSinceEpoch;
  int getInt(String key, [int fallback = 0]) => _prefs.getInt(key) ?? fallback;
  void setInt(String key, int value) => _prefs.setInt(key, value);
  String getString(String key, [String fallback = '']) =>
      _prefs.getString(key) ?? fallback;
  void setString(String key, String value) => _prefs.setString(key, value);
  bool getBool(String key) => _prefs.getBool(key) ?? false;

  String get resolution => getString('preferredResolution', '1080p');
  set resolution(String value) => setString('preferredResolution', value);

  String get connection => _connection;
  Future<void> saveConnection(String link) async {
    await _secure.write(key: 'debridio', value: link);
    _connection = link;
  }

  Future<void> clearConnection() async {
    await _secure.delete(key: 'debridio');
    _connection = '';
  }

  bool saved(Meta m) => getBool('saved:${m['id']}');
  bool watched(Meta m) => getInt('opened:${m['id']}') > 0;

  void toggleSaved(Meta m) {
    final add = !saved(m);
    _prefs.setBool('saved:${m['id']}', add);
    remember(m);
    for (final g in genres(m)) {
      setInt(
        'genre:$g',
        (getInt('genre:$g') + (add ? 1 : -1)).clamp(0, 1 << 30),
      );
    }
  }

  void remember(Meta m) {
    final id = str(m, 'id');
    final merged = {...?recalled(id), ...m};
    _metaCache[id] = merged;
    setString('meta:$id', jsonEncode(merged));
  }

  Meta? recalled(String id) {
    if (_metaCache.containsKey(id)) return _metaCache[id];
    final raw = _prefs.getString('meta:$id');
    if (raw == null) return null;
    try {
      return _metaCache[id] = Map<String, dynamic>.from(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  WatchProgress progress(Meta meta, {String? video}) {
    final id = str(meta, 'id');
    final current =
        video ?? getString('video:$id', str(meta, 'type') == 'movie' ? id : '');
    Map<String, dynamic>? episode;
    for (final source in [meta, recalled(id)]) {
      final videos = source?['videos'];
      if (videos is List) {
        for (final item in videos.whereType<Map>()) {
          if ('${item['id']}' == current) {
            episode = Map<String, dynamic>.from(item);
            break;
          }
        }
      }
      if (episode != null) break;
    }
    if (episode == null) {
      try {
        final snapshot = jsonDecode(getString('episode:$current', '{}'));
        if (snapshot is Map && snapshot.isNotEmpty) {
          episode = Map<String, dynamic>.from(snapshot);
        }
      } catch (_) {}
    }
    return WatchProgress(
      videoId: current,
      positionMs: getInt('position:$current'),
      durationMs: getInt('duration:$current'),
      episode: episode,
    );
  }

  void recordPlayback(Meta meta, String video) {
    final id = str(meta, 'id');
    remember(meta);
    setInt('opened:$id', now());
    setInt('played:$id', now());
    setString('video:$id', video);
    final episode = progress(meta, video: video).episode;
    if (episode != null) setString('episode:$video', jsonEncode(episode));
    playbackChanges.value++;
  }

  void saveProgress(String video, int position, int duration) {
    setInt('position:$video', position);
    setInt('duration:$video', duration);
    playbackChanges.value++;
  }

  void learn(Meta m) {
    final key = 'learned:${m['id']}';
    if (getBool(key)) return;
    _prefs.setBool(key, true);
    for (final g in genres(m)) {
      setInt('genre:$g', getInt('genre:$g') + 1);
    }
  }

  int peakGenre() {
    var peak = 0;
    for (final k in _prefs.getKeys()) {
      if (k.startsWith('genre:')) peak = peak > getInt(k) ? peak : getInt(k);
    }
    return peak;
  }

  int affinity(Meta m) => genres(m).fold(0, (n, g) => n + getInt('genre:$g'));

  List<String> savedIds() => _prefs
      .getKeys()
      .where((k) => k.startsWith('saved:') && getBool(k))
      .map((k) => k.substring(6))
      .toList();

  List<String> keys() => _prefs.getKeys().toList();

  Future<void> reset() async {
    _metaCache.clear();
    await _prefs.clear();
    playbackChanges.value++;
  }
}

List<String> genres(Meta m) {
  final g = m['genres'] ?? m['genre'];
  return g is List ? g.map((e) => '$e').toList() : const [];
}

String str(Meta m, String key) {
  final v = m[key];
  return v == null ? '' : '$v';
}
