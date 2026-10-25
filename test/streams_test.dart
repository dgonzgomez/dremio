import 'package:dremio/streams.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> stream(String url, String title) => {'url': url, 'name': 'Source', 'title': title};

void main() {
  final streams = [stream('https://a.example/1', '1080p HDR10 x265'), stream('https://a.example/2', '1080p x264'), stream('https://a.example/3', '1080p DoVi')];

  test('HDR streams are kept when HDR is on', () {
    expect(selectStreams(streams, '1080p').length, 3);
  });

  test('HDR streams are skipped when HDR is off', () {
    final kept = selectStreams(streams, '1080p', hdr: false);
    expect(kept.map((c) => c.url), ['https://a.example/2']);
  });

  test('Torrentio cached marker ranks above uncached', () {
    final ranked = selectStreams([stream('https://t.example/1', '[RD download] 1080p'), stream('https://t.example/2', '[RD+] 1080p')], '1080p');
    expect(ranked.first.url, 'https://t.example/2');
  });

  test('Data Saver puts files under 7 GB first and big ones last', () {
    final sized = [stream('https://s.example/big', '1080p x264 💾 12.4 GB'), stream('https://s.example/unknown', '1080p'), stream('https://s.example/small', '1080p 💾 3.1 GB')];
    expect(selectStreams(sized, '1080p', dataSaver: true).map((c) => c.url), ['https://s.example/small', 'https://s.example/unknown', 'https://s.example/big']);
    expect(selectStreams(sized, '1080p').first.url, 'https://s.example/big');
    expect(streamSizeGb(stream('https://s.example/m', '720p 850 MB'))!, closeTo(.83, .01));
  });

  test('source links are checked against their host', () {
    expect(sourceById('torrentio').accepts('https://torrentio.strem.fun/realdebrid=x/manifest.json'), isTrue);
    expect(sourceById('torrentio').accepts('https://evil.example/manifest.json'), isFalse);
    expect(sourceById('debridio').accepts('http://addon.debridio.com/x/manifest.json'), isFalse);
    expect(sourceById('comet').accepts('https://comet.example/abc/manifest.json'), isTrue);
  });
}
