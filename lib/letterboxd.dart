import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'catalog.dart';
import 'net.dart';
import 'store.dart';

/// One film from a member's public diary feed.
class DiaryEntry {
  const DiaryEntry({required this.user, required this.tmdb, required this.title, required this.year, required this.watched, this.rating, this.liked = false, this.rewatch = false, this.poster = ''});
  final String user, tmdb, title, year, poster;
  final DateTime watched;

  /// Stars out of 5, in halves; null when unrated.
  final double? rating;
  final bool liked, rewatch;

  /// Loved enough to recommend to a friend.
  bool get loved => liked || (rating ?? 0) >= 4;

  Map<String, dynamic> toJson() => {
    'user': user,
    'tmdb': tmdb,
    'title': title,
    'year': year,
    'watched': watched.toIso8601String(),
    'rating': rating,
    'liked': liked,
    'rewatch': rewatch,
    'poster': poster,
  };

  factory DiaryEntry.fromJson(Map j) => DiaryEntry(
    user: '${j['user']}',
    tmdb: '${j['tmdb']}',
    title: '${j['title']}',
    year: '${j['year']}',
    watched: DateTime.tryParse('${j['watched']}') ?? DateTime(2000),
    rating: (j['rating'] as num?)?.toDouble(),
    liked: j['liked'] == true,
    rewatch: j['rewatch'] == true,
    poster: '${j['poster'] ?? ''}',
  );
}

String stars(double rating) => '★' * rating.floor() + (rating % 1 >= .5 ? '½' : '');

class Member {
  const Member(this.username, this.name, this.avatar);
  final String username, name, avatar;
  Map<String, dynamic> toJson() => {'username': username, 'name': name, 'avatar': avatar};
  factory Member.fromJson(Map j) => Member('${j['username']}', '${j['name']}', '${j['avatar'] ?? ''}');
}

/// How two diaries line up.
class Blend {
  const Blend(this.friend, this.match, this.shared, this.forYou, this.bothLoved);
  final Member friend;

  /// 0–100 from how closely shared ratings agree; null with too few rated films in common.
  final int? match;
  final int shared;

  /// Films the friend loved that you haven't logged or played.
  final List<DiaryEntry> forYou;
  final List<DiaryEntry> bothLoved;
}

/// Letterboxd through its public pages only: diaries from each member's RSS feed, profiles and
/// follows from their following page. Nothing is written back; logging happens on Letterboxd itself.
class Letterboxd {
  Letterboxd._();
  static final instance = Letterboxd._();
  static const _site = 'https://letterboxd.com';
  static final _client = http.Client();

  static bool validUsername(String u) => RegExp(r'^[A-Za-z0-9_]{2,40}$').hasMatch(u);
  static Uri film(String imdbId) => Uri.parse('$_site/imdb/$imdbId/');
  static Uri profileUrl(String user) => Uri.parse('$_site/$user/');

  // Account ------------------------------------------------------------------

  /// Bumped whenever the linked account or friends change.
  final changes = ValueNotifier(0);
  Store get _store => Store.instance;

  String get user => _store.getString('letterboxd');
  bool get linked => user.isNotEmpty;

  Member? get me {
    try {
      return linked ? Member.fromJson(jsonDecode(_store.getString('lb:me')) as Map) : null;
    } catch (_) {
      return Member(user, user, '');
    }
  }

  List<Member> get friends {
    try {
      return [for (final j in jsonDecode(_store.getString('lb:friends', '[]')) as List) Member.fromJson(j as Map)];
    } catch (_) {
      return const [];
    }
  }

  set friends(List<Member> list) {
    _store.setString('lb:friends', jsonEncode([for (final m in list) m.toJson()]));
    changes.value++;
  }

  /// Checks the member exists and has a public diary, then links them as you.
  Future<Member> link(String username) async {
    final member = await profile(username.trim(), fresh: true);
    _store.setString('letterboxd', member.username);
    _store.setString('lb:me', jsonEncode(member.toJson()));
    changes.value++;
    return member;
  }

  void unlink() {
    _store.setString('letterboxd', '');
    _store.setString('lb:me', '');
    _store.setString('lb:friends', '[]');
    changes.value++;
  }

  Future<Member> addFriend(String username) async {
    final member = await profile(username.trim(), fresh: true);
    if (member.username != user && !friends.any((f) => f.username == member.username)) friends = [...friends, member];
    return member;
  }

  void removeFriend(String username) => friends = friends.where((f) => f.username != username).toList();

  /// Adds everyone you follow on Letterboxd; returns how many were new.
  Future<int> importFollowing() async {
    final current = friends;
    final added = (await following(user)).where((m) => !current.any((f) => f.username == m.username)).toList();
    friends = [...current, ...added];
    return added.length;
  }

  // Feeds ---------------------------------------------------------------------

  final _diaries = <String, List<DiaryEntry>>{};
  final _loads = <String, Future<List<DiaryEntry>>>{};
  Directory? _dir;

  Future<Directory> _cache() async {
    final dir = _dir ??= Directory('${(await getApplicationSupportDirectory()).path}/letterboxd');
    await dir.create(recursive: true);
    return dir;
  }

  Future<String> _get(String url) async {
    final response = await _client.get(Uri.parse(url), headers: {'User-Agent': userAgent}).timeout(const Duration(seconds: 15));
    if (response.statusCode == 404) throw const LetterboxdMissing();
    if (response.statusCode != 200) throw http.ClientException('HTTP ${response.statusCode}', Uri.parse(url));
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  /// Cached copy of [url] if younger than [maxAge]; otherwise fetched, falling back to a stale copy offline.
  Future<String> _cached(String name, String url, Duration maxAge, {bool fresh = false}) async {
    final file = File('${(await _cache()).path}/$name');
    final exists = file.existsSync();
    if (!fresh && exists && DateTime.now().difference(file.lastModifiedSync()) < maxAge) return file.readAsString();
    try {
      final body = await _get(url);
      await file.writeAsString(body);
      return body;
    } catch (e) {
      if (exists && e is! LetterboxdMissing) return file.readAsString();
      rethrow;
    }
  }

  List<DiaryEntry> diaryOf(String user) => _diaries[user.toLowerCase()] ?? const [];

  /// The member's last 100 diary entries, newest first.
  Future<List<DiaryEntry>> diary(String user, {bool fresh = false}) {
    final key = user.toLowerCase();
    if (fresh) _loads.remove(key);
    return _loads[key] ??= () async {
      try {
        final xml = await _cached('rss-$key.xml', '$_site/$key/rss/', const Duration(hours: 2), fresh: fresh);
        return _diaries[key] = parseRss(key, xml);
      } catch (e) {
        _loads.remove(key);
        rethrow;
      }
    }();
  }

  static String _tag(String item, String tag) {
    final m = RegExp('<$tag>(.*?)</$tag>', dotAll: true).firstMatch(item);
    return m == null ? '' : _unescape(m[1]!.replaceAll(RegExp(r'^<!\[CDATA\[|\]\]>$'), '').trim());
  }

  static String _unescape(String s) => s.replaceAll('&amp;', '&').replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&#039;', "'").replaceAll('&#39;', "'");

  @visibleForTesting
  static List<DiaryEntry> parseRss(String user, String xml) {
    final out = <DiaryEntry>[];
    for (final item in xml.split('<item>').skip(1)) {
      final tmdb = _tag(item, 'tmdb:movieId');
      final title = _tag(item, 'letterboxd:filmTitle');
      if (tmdb.isEmpty || title.isEmpty) continue; // lists and other activity
      final watched = DateTime.tryParse(_tag(item, 'letterboxd:watchedDate')) ?? DateTime.tryParse(_tag(item, 'pubDate')) ?? DateTime(2000);
      out.add(
        DiaryEntry(
          user: user,
          tmdb: tmdb,
          title: title,
          year: _tag(item, 'letterboxd:filmYear'),
          watched: watched,
          rating: double.tryParse(_tag(item, 'letterboxd:memberRating')),
          liked: _tag(item, 'letterboxd:memberLike') == 'Yes',
          rewatch: _tag(item, 'letterboxd:rewatch') == 'Yes',
          poster: RegExp(r'<img src="([^"]+)"').firstMatch(item)?.group(1) ?? '',
        ),
      );
    }
    out.sort((a, b) => b.watched.compareTo(a.watched));
    return out;
  }

  /// The page owner and the members on one page of their following list.
  @visibleForTesting
  static ({Member? owner, List<Member> following}) parseFollowing(String user, String html) {
    Member? owner;
    final mini = RegExp(r'class="avatar -a24" href="/([^/"]+)/"\s*>\s*<img src="([^"]+)" alt="([^"]*)"').firstMatch(html);
    if (mini != null && mini[1]!.toLowerCase() == user.toLowerCase()) owner = Member(mini[1]!.toLowerCase(), _unescape(mini[3]!), _sharpen(_unescape(mini[2]!)));
    final following = <Member>[];
    for (final m in RegExp(r'class="avatar -a40" href="/([^/"]+)/"\s*>\s*<img src="([^"]+)" alt="([^"]*)"').allMatches(html)) {
      final name = m[1]!.toLowerCase();
      if (name == user.toLowerCase() || following.any((f) => f.username == name)) continue;
      following.add(Member(name, _unescape(m[3]!), _sharpen(_unescape(m[2]!))));
    }
    return (owner: owner, following: following);
  }

  /// Asks for a larger avatar than the tiny one in the page.
  static String _sharpen(String url) => url.replaceAll(RegExp(r'size=48'), 'size=160').replaceAll('-0-80-0-80-crop', '-0-220-0-220-crop').replaceAll('-0-48-0-48-crop', '-0-220-0-220-crop');

  /// Name and avatar for [user]. Throws [LetterboxdMissing] for unknown members.
  Future<Member> profile(String user, {bool fresh = false}) async {
    final key = user.toLowerCase();
    final rss = await _cached('rss-$key.xml', '$_site/$key/rss/', const Duration(hours: 2), fresh: fresh);
    _diaries[key] = parseRss(key, rss);
    final title = RegExp(r'<title>Letterboxd - (.*?)</title>').firstMatch(rss)?.group(1);
    Member? owner;
    try {
      owner = parseFollowing(key, await _cached('following-$key.html', '$_site/$key/following/', const Duration(days: 1), fresh: fresh)).owner;
    } catch (_) {}
    return Member(key, owner?.name ?? _unescape(title ?? key), owner?.avatar ?? '');
  }

  /// Everyone [user] follows. Letterboxd blocks quick repeat pages, so this may stop after the first.
  Future<List<Member>> following(String user) async {
    final key = user.toLowerCase();
    final out = parseFollowing(key, await _cached('following-$key.html', '$_site/$key/following/', const Duration(days: 1), fresh: true)).following;
    for (var page = 2; page <= 6 && out.length == (page - 1) * 25; page++) {
      try {
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        out.addAll(parseFollowing(key, await _get('$_site/$key/following/page/$page/')).following.where((m) => !out.any((o) => o.username == m.username)));
      } catch (_) {
        break;
      }
    }
    return out;
  }

  /// Playable movie for a diary entry, via TMDB's IMDb id. Cached once found.
  Future<Meta?> meta(DiaryEntry entry) async {
    final store = Store.instance;
    var imdb = store.getString('lb:tmdb:${entry.tmdb}');
    if (imdb.isNotEmpty) {
      final known = store.recalled(imdb);
      if (known != null) return known;
    }
    try {
      final raw = await getJson('https://tmdb.elfhosted.com/meta/movie/tmdb:${entry.tmdb}.json');
      final m = raw is Map ? raw['meta'] : null;
      if (m is! Map) return null;
      final meta = Map<String, dynamic>.from(m);
      imdb = '${meta['imdb_id'] ?? ''}';
      if (!imdb.startsWith('tt')) return null;
      final slim = Catalog.slim(meta, 'movie', imdb);
      store.setString('lb:tmdb:${entry.tmdb}', imdb);
      store.remember(slim);
      return slim;
    } catch (_) {
      return null;
    }
  }

  /// Metas for [entries] in order, skipping films Dremio can't find; a few lookups at a time.
  Future<List<(DiaryEntry, Meta)>> metas(List<DiaryEntry> entries) async {
    final out = List<(DiaryEntry, Meta)?>.filled(entries.length, null);
    var next = 0;
    Future<void> worker() async {
      while (next < entries.length) {
        final i = next++;
        final m = await meta(entries[i]);
        if (m != null) out[i] = (entries[i], m);
      }
    }

    await Future.wait(List.generate(6, (_) => worker()));
    return out.whereType<(DiaryEntry, Meta)>().toList();
  }

  /// How many recent diary entries from each side a blend compares.
  static const blendWindow = 50;

  /// Your recent diary against a friend's. [played] holds TMDB ids of films you've watched in Dremio.
  static Blend blend(Member friend, List<DiaryEntry> mine, List<DiaryEntry> theirs, Set<String> played) {
    mine = mine.take(blendWindow).toList();
    theirs = theirs.take(blendWindow).toList();
    final my = {for (final e in mine) e.tmdb: e};
    final seen = {...my.keys, ...played};
    final rated = <double>[];
    var shared = 0;
    final bothLoved = <DiaryEntry>[];
    final forYou = <DiaryEntry>[];
    final done = <String>{};
    for (final e in theirs) {
      if (!done.add(e.tmdb)) continue;
      final m = my[e.tmdb];
      if (m != null) {
        shared++;
        if (m.rating != null && e.rating != null) rated.add((m.rating! - e.rating!).abs());
        if (m.loved && e.loved) bothLoved.add(e);
      } else if (e.loved && !seen.contains(e.tmdb)) {
        forYou.add(e);
      }
    }
    final match = rated.length < 3 ? null : (100 - rated.reduce((a, b) => a + b) / rated.length / 4.5 * 100).round().clamp(0, 100);
    forYou.sort((a, b) => (b.rating ?? 4).compareTo(a.rating ?? 4));
    return Blend(friend, match, shared, forYou, bothLoved);
  }
}

class LetterboxdMissing implements Exception {
  const LetterboxdMissing();
}
