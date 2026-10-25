import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef Meta = Map<String, dynamic>;

/// Local library and taste profile. Keys match the Fire TV app.
class Store {
  Store._(this._prefs);
  final SharedPreferences _prefs;
  static late Store instance;
  static const _secure = FlutterSecureStorage(mOptions: MacOsOptions(usesDataProtectionKeychain: false));
  String _connection = '';

  static Future<void> open() async {
    instance = Store._(await SharedPreferences.getInstance());
    try {
      instance._connection = await _secure.read(key: 'debridio') ?? '';
    } catch (_) {}
  }

  int now() => DateTime.now().millisecondsSinceEpoch;
  int getInt(String key) => _prefs.getInt(key) ?? 0;
  void setInt(String key, int value) => _prefs.setInt(key, value);
  String getString(String key, [String fallback = '']) => _prefs.getString(key) ?? fallback;
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
      setInt('genre:$g', (getInt('genre:$g') + (add ? 1 : -1)).clamp(0, 1 << 30));
    }
  }

  void remember(Meta m) => setString('meta:${m['id']}', jsonEncode(m));

  Meta? recalled(String id) {
    final raw = _prefs.getString('meta:$id');
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw));
    } catch (_) {
      return null;
    }
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

  List<String> savedIds() => _prefs.getKeys().where((k) => k.startsWith('saved:') && getBool(k)).map((k) => k.substring(6)).toList();

  List<String> keys() => _prefs.getKeys().toList();

  Future<void> reset() => _prefs.clear();
}

List<String> genres(Meta m) {
  final g = m['genres'] ?? m['genre'];
  return g is List ? g.map((e) => '$e').toList() : const [];
}

String str(Meta m, String key) {
  final v = m[key];
  return v == null ? '' : '$v';
}
