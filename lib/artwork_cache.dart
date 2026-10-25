import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

import 'net.dart';

/// Compressed artwork survives restarts. Decoded images remain in Flutter's LRU.
/// The disk quota and limited network concurrency are especially useful on Fire TV.
class ArtworkCache {
  ArtworkCache({
    required this.directory,
    this.maxBytes = 128 * 1024 * 1024,
    this.maxFiles = 1200,
    this.maxAge = const Duration(days: 30),
    this.concurrency = 3,
    HttpClient? client,
  }) : _client = client ?? HttpClient();
  static late ArtworkCache instance;
  final Directory directory;
  final int maxBytes, maxFiles, concurrency;
  final Duration maxAge;
  final HttpClient _client;
  final _pending = <String, Future<Uint8List>>{};
  final _waiting = Queue<Completer<void>>();
  int _active = 0, _writes = 0;
  Future<void>? _pruning;

  static Future<void> open() async {
    final root = await getApplicationCacheDirectory();
    instance = ArtworkCache(directory: Directory('${root.path}/artwork-v1'));
    await instance.directory.create(recursive: true);
    unawaited(instance.prune());
  }

  File _file(String url) =>
      File('${directory.path}/${sha256.convert(utf8.encode(url))}.image');

  Future<Uint8List> get(String url) => _pending.putIfAbsent(url, () async {
    try {
      return await _get(url);
    } finally {
      _pending.remove(url);
    }
  });

  Future<Uint8List> _get(String url) async {
    final uri = Uri.parse(url);
    if (uri.scheme != 'https') {
      throw const FormatException('Artwork requires HTTPS');
    }
    final file = _file(url);
    try {
      final stat = await file.stat();
      if (stat.type == FileSystemEntityType.file &&
          DateTime.now().difference(stat.modified) < maxAge) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          unawaited(
            file.setLastModified(DateTime.now()).catchError((_) => file),
          );
          return bytes;
        }
      }
    } on FileSystemException {
      // A missing or evicted file is an ordinary cache miss.
    }
    await _acquire();
    try {
      final request = await _client
          .getUrl(uri)
          .timeout(const Duration(seconds: 12));
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw const HttpException('Artwork is unavailable');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 15))) {
        bytes.add(chunk);
        if (bytes.length > 8 * 1024 * 1024) {
          throw const FormatException('Artwork is too large');
        }
      }
      final result = bytes.takeBytes();
      if (result.isEmpty) throw const FormatException('Empty artwork');
      try {
        await directory.create(recursive: true);
        final temporary = File('${file.path}.part');
        await temporary.writeAsBytes(result);
        await temporary.rename(file.path);
        if (++_writes >= 16) {
          _writes = 0;
          unawaited(prune());
        }
      } on FileSystemException {
        // A full/unavailable disk must not prevent the picture from displaying.
      }
      return result;
    } finally {
      _release();
    }
  }

  Future<void> _acquire() async {
    if (_active < concurrency) {
      _active++;
      return;
    }
    final permit = Completer<void>();
    _waiting.add(permit);
    await permit.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete();
    } else {
      _active--;
    }
  }

  Future<void> remove(String url) async {
    try {
      await _file(url).delete();
    } on FileSystemException {
      /* Already absent. */
    }
  }

  Future<void> prune() =>
      _pruning ??= _trim().whenComplete(() => _pruning = null);

  Future<void> _trim() async {
    try {
      final entries = <({File file, FileStat stat})>[];
      await for (final entity in directory.list()) {
        if (entity is! File || !entity.path.endsWith('.image')) continue;
        final stat = await entity.stat();
        entries.add((file: entity, stat: stat));
      }
      entries.sort((a, b) => b.stat.modified.compareTo(a.stat.modified));
      var bytes = 0, count = 0;
      for (final entry in entries) {
        bytes += entry.stat.size;
        count++;
        if (bytes > maxBytes ||
            count > maxFiles ||
            DateTime.now().difference(entry.stat.modified) > maxAge) {
          try {
            await entry.file.delete();
          } on FileSystemException {
            /* Concurrent eviction is harmless. */
          }
        }
      }
    } on FileSystemException {
      /* The operating system may clear its cache directory. */
    }
  }

  void close() => _client.close(force: true);
}

class DiskArtworkImage extends ImageProvider<DiskArtworkImage> {
  const DiskArtworkImage(this.url);
  final String url;
  @override
  Future<DiskArtworkImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(
    DiskArtworkImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(codec: _decode(key, decode), scale: 1);
  Future<ui.Codec> _decode(
    DiskArtworkImage key,
    ImageDecoderCallback decode,
  ) async {
    try {
      final bytes = await ArtworkCache.instance.get(key.url);
      return await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } catch (_) {
      await ArtworkCache.instance.remove(key.url);
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is DiskArtworkImage && other.url == url;
  @override
  int get hashCode => url.hashCode;
}

/// Share exact decode keys between visible artwork and carousel prefetching.
ImageProvider artworkProvider(
  String url,
  double logicalWidth,
  double pixelRatio,
) {
  final limit = Platform.isAndroid ? 1280 : 2560;
  final pixels = ((logicalWidth * pixelRatio / 32).ceil() * 32).clamp(
    64,
    limit,
  );
  return ResizeImage.resizeIfNeeded(pixels, null, DiskArtworkImage(url));
}
