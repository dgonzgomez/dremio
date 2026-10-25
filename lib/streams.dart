import 'dart:async';
import 'dart:io';

import 'net.dart';
import 'store.dart';

class StreamChoice {
  StreamChoice(Map<String, dynamic> stream, String preferred)
    : url = '${stream['url']}',
      quality = streamQuality(stream),
      score = rank(stream, preferred),
      label = streamLabel(stream, streamQuality(stream)),
      headers = _headers(stream);
  final String url, quality, label;
  final int score;
  final Map<String, String> headers;

  static Map<String, String> _headers(Map<String, dynamic> stream) {
    final request = (((stream['behaviorHints'] as Map?)?['proxyHeaders'] as Map?)?['request'] as Map?) ?? const {};
    return {
      for (final e in request.entries)
        if (RegExp(r'^[A-Za-z0-9-]+$').hasMatch('${e.key}') && !'${e.value}'.contains('\n') && !'${e.value}'.contains('\r')) '${e.key}': '${e.value}',
    };
  }
}

String _description(Map<String, dynamic> s) => '${s['name'] ?? ''} ${s['title'] ?? ''} ${s['description'] ?? ''} ${(s['behaviorHints'] as Map?)?['filename'] ?? ''}'.toLowerCase();

String streamQuality(Map<String, dynamic> s) {
  final t = _description(s);
  if (t.contains('2160') || t.contains('4k')) return '4K';
  for (final q in ['1080p', '720p', '480p', '360p']) {
    if (t.contains(q)) return q;
  }
  return 'Auto';
}

String streamLabel(Map<String, dynamic> s, String quality) {
  var detail = '${s['title'] ?? s['description'] ?? ''}';
  if (detail.isEmpty) detail = '${s['name'] ?? ''}';
  final out = StringBuffer(quality);
  for (final line in detail.split('\n').take(2)) {
    if (line.trim().isNotEmpty) out.write('  ·  ${line.trim()}');
  }
  final value = out.toString();
  return value.length > 140 ? '${value.substring(0, 140)}…' : value;
}

int rank(Map<String, dynamic> s, String preferred) {
  final t = _description(s), q = streamQuality(s);
  var n = 0;
  if (t.contains('⚡') || t.contains('cached')) n += 200;
  if (t.contains('uncached') || t.contains('download')) n -= 800;
  n += q == preferred
      ? (q == '4K' ? 840 : 440)
      : q == '1080p'
      ? 300
      : q == '720p'
      ? 230
      : q == '480p'
      ? 130
      : q == '4K'
      ? -900
      : 50;
  if (t.contains('x264') || t.contains('h264') || t.contains('h.264')) n += 90;
  if (t.contains('x265') || t.contains('hevc')) n -= 70;
  if (t.contains('hdr') || t.contains('10bit') || t.contains('10 bit')) n -= 170;
  if (t.contains('dv|') || t.contains('dolby vision') || t.contains('av1') || t.contains('8k')) n -= 600;
  if (t.contains('english') || t.contains('eng') || t.contains('🇬🇧') || t.contains('🇺🇸')) n += 40;
  if (t.contains('aac')) n += 30;
  return n;
}

class NoConnection implements Exception {}

Future<List<StreamChoice>> resolveStreams(String type, String video) async {
  final manifest = Store.instance.connection;
  if (manifest.isEmpty) throw NoConnection();
  final base = manifest.substring(0, manifest.lastIndexOf('/'));
  final response = await getJson('$base/stream/${Uri.encodeComponent(type)}/${Uri.encodeComponent(video)}.json', timeout: const Duration(seconds: 40));
  return selectStreams(response is Map ? response['streams'] : null, Store.instance.resolution);
}

List<StreamChoice> selectStreams(dynamic streams, String preferred) {
  final seen = <String>{};
  final choices = <StreamChoice>[];
  for (final raw in streams is List ? streams : const []) {
    if (raw is! Map) continue;
    final stream = Map<String, dynamic>.from(raw);
    final uri = Uri.tryParse('${stream['url'] ?? ''}');
    final t = _description(stream);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) continue;
    if (t.contains('8k') || (streamQuality(stream) == '4K' && preferred != '4K') || t.contains('dolby vision') || t.contains('dv|')) continue;
    if (seen.add(uri.toString())) choices.add(StreamChoice(stream, preferred));
  }
  choices.sort((a, b) => b.score.compareTo(a.score));
  return choices.take(8).toList();
}

class OnlineSubtitle {
  const OnlineSubtitle(this.url, this.language, this.name);
  final String url, language, name;
}

const _subtitleLanguages = {'eng': ('English', 3), 'spa': ('Spanish', 2)};

/// Subtitles for the title from OpenSubtitles (via Stremio's public add-on), for sources that ship without them.
Future<List<OnlineSubtitle>> onlineSubtitles(String type, String video) async {
  final response = await getJson('https://opensubtitles-v3.strem.io/subtitles/${Uri.encodeComponent(type)}/${Uri.encodeComponent(video)}.json');
  final taken = <String, int>{};
  final found = <OnlineSubtitle>[];
  for (final s in response is Map && response['subtitles'] is List ? response['subtitles'] as List : const []) {
    if (s is! Map) continue;
    final language = '${s['lang'] ?? ''}', wanted = _subtitleLanguages[language];
    final uri = Uri.tryParse('${s['url'] ?? ''}');
    if (wanted == null || uri == null || uri.scheme != 'https') continue;
    final n = taken[language] = (taken[language] ?? 0) + 1;
    if (n <= wanted.$2) found.add(OnlineSubtitle(uri.toString(), language, '${wanted.$1} · online $n'));
  }
  return found;
}

/// Confirms the link serves video before handing it to the player.
Future<String> preflight(StreamChoice choice) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 9);
  try {
    var address = Uri.parse(choice.url);
    for (var hop = 0; hop < 6; hop++) {
      final request = await client.getUrl(address);
      request.followRedirects = false;
      request.headers.set('User-Agent', userAgent);
      request.headers.set('Range', 'bytes=0-8191');
      choice.headers.forEach(request.headers.set);
      final response = await request.close().timeout(const Duration(seconds: 12));
      if (response.isRedirect) {
        final location = response.headers.value('location');
        await response.drain<void>();
        if (location == null) throw const HttpException('Missing redirect');
        address = address.resolve(location);
        if (address.scheme != 'https') throw const HttpException('Insecure redirect');
        continue;
      }
      if (response.statusCode != 200 && response.statusCode != 206) throw const HttpException('Media unavailable');
      final mime = response.headers.contentType?.mimeType ?? '';
      if (mime.contains('text/html') || mime.contains('application/json')) throw const HttpException('Not a video');
      await response.first.timeout(const Duration(seconds: 12));
      return address.toString();
    }
    throw const HttpException('Too many redirects');
  } finally {
    client.close(force: true);
  }
}

Future<void> checkManifest(String link) async {
  final manifest = await getJson(link);
  if (manifest is! Map || !manifest.containsKey('resources')) throw const HttpException('Not an add-on');
}

bool validDebridioLink(String link) {
  final uri = Uri.tryParse(link.trim());
  return uri != null && uri.scheme == 'https' && uri.host.toLowerCase() == 'addon.debridio.com' && uri.path.endsWith('/manifest.json') && !uri.hasQuery;
}
