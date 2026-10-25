import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dremio/artwork_cache.dart';
import 'package:flutter_test/flutter_test.dart';

class Headers extends Fake implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class Images extends Fake implements HttpClient {
  int requests = 0, active = 0, peak = 0;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requests++;
    active++;
    if (active > peak) peak = active;
    return Request(this);
  }

  @override
  void close({bool force = false}) {}
}

class Request extends Fake implements HttpClientRequest {
  Request(this.images);
  final Images images;
  @override
  final headers = Headers();
  @override
  Future<HttpClientResponse> close() async => Response(images);
}

class Response extends Stream<List<int>> implements HttpClientResponse {
  Response(this.images);
  final Images images;
  @override
  int get statusCode => HttpStatus.ok;
  Stream<List<int>> get bytes async* {
    await Future<void>.delayed(const Duration(milliseconds: 15));
    yield Uint8List.fromList([1, 2, 3, 4]);
    images.active--;
  }

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => bytes.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('dremio-artwork-test-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'disk artwork survives a cache instance restart without a download',
    () async {
      final first = Images(), second = Images();
      final cache = ArtworkCache(directory: directory, client: first);
      expect(await cache.get('https://images.example/poster'), [1, 2, 3, 4]);
      cache.close();
      final restarted = ArtworkCache(directory: directory, client: second);
      expect(await restarted.get('https://images.example/poster'), [
        1,
        2,
        3,
        4,
      ]);
      expect(first.requests, 1);
      expect(second.requests, 0);
      restarted.close();
    },
  );
  test(
    'identical image loads coalesce and other loads respect concurrency',
    () async {
      final images = Images();
      final cache = ArtworkCache(
        directory: directory,
        client: images,
        concurrency: 2,
      );
      await Future.wait(
        List.generate(10, (_) => cache.get('https://images.example/same')),
      );
      expect(images.requests, 1);
      await Future.wait(
        List.generate(8, (i) => cache.get('https://images.example/$i')),
      );
      expect(images.peak, lessThanOrEqualTo(2));
      cache.close();
    },
  );
  test('cache eviction enforces its byte quota', () async {
    final cache = ArtworkCache(
      directory: directory,
      client: Images(),
      maxBytes: 8,
    );
    for (var i = 0; i < 5; i++) {
      await cache.get('https://images.example/$i');
    }
    await cache.prune();
    final files = await directory
        .list()
        .where((f) => f.path.endsWith('.image'))
        .toList();
    expect(files.length, 2);
    cache.close();
  });
}
