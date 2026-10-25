import 'dart:io';

import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'net.dart';

const _repo = 'dgonzgomez/dremio';
const _channel = MethodChannel('dremio/update');

class Release {
  const Release(this.version, this.download);
  final String version;
  final Uri? download;
}

String get _assetName => Platform.isAndroid
    ? 'Dremio-android-arm.apk'
    : Platform.isWindows
    ? 'Dremio-windows-x64.zip'
    : 'Dremio-macos.zip';

Future<String> currentVersion() async => (await PackageInfo.fromPlatform()).version;

/// The newest published GitHub release, with the download for this platform if it has one.
Future<Release> latestRelease() async {
  final release = await getJson('https://api.github.com/repos/$_repo/releases/latest');
  if (release is! Map) throw const FormatException('Unexpected release');
  final version = '${release['tag_name'] ?? ''}'.replaceFirst(RegExp('^v'), '');
  Uri? download;
  for (final asset in release['assets'] is List ? release['assets'] as List : const []) {
    if (asset is! Map || asset['name'] != _assetName) continue;
    final uri = Uri.tryParse('${asset['browser_download_url'] ?? ''}');
    if (uri != null && uri.scheme == 'https' && uri.host == 'github.com' && uri.path.startsWith('/$_repo/releases/download/')) download = uri;
  }
  return Release(version, download);
}

/// Whether dotted version [a] is newer than [b].
bool isNewer(String a, String b) {
  List<int> parts(String v) => v.split(RegExp(r'[.+-]')).take(3).map((p) => int.tryParse(p) ?? 0).toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final l = i < x.length ? x[i] : 0, r = i < y.length ? y[i] : 0;
    if (l != r) return l > r;
  }
  return false;
}

Future<File> download(Uri url, void Function(double progress) onProgress) async {
  final dir = Directory('${(await getTemporaryDirectory()).path}/updates');
  await dir.create(recursive: true);
  final file = File('${dir.path}/${Platform.isAndroid ? 'dremio.apk' : _assetName}');
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    request.headers.set('User-Agent', userAgent);
    final response = await request.close();
    if (response.statusCode != 200) throw HttpException('HTTP ${response.statusCode}');
    final total = response.contentLength;
    var received = 0;
    final sink = file.openWrite();
    await for (final chunk in response) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) onProgress(received / total);
    }
    await sink.close();
    return file;
  } finally {
    client.close();
  }
}

/// Hands the download to the platform. Returns a message to show, or null when the app is about to restart.
Future<String?> install(File file, String version) async {
  if (Platform.isAndroid) {
    final started = await _channel.invokeMethod<bool>('install') ?? false;
    return started ? 'Confirm the install on screen.' : 'Allow Dremio to install apps, then try again.';
  }
  if (Platform.isWindows) {
    final folder = File(Platform.resolvedExecutable).parent;
    try {
      final probe = File('${folder.path}/.dremio-update-check');
      await probe.writeAsString('');
      await probe.delete();
    } on FileSystemException {
      return 'Dremio can’t update itself in ${folder.path}. Move the Dremio folder somewhere like Documents, or download the new zip from GitHub.';
    }
    final script = File('${file.parent.path}/update.ps1');
    await script.writeAsString(_windowsScript);
    await Process.start('powershell.exe', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-WindowStyle',
      'Hidden',
      '-File',
      script.path,
      '-ProcessId',
      '$pid',
      '-Zip',
      file.path,
      '-Target',
      folder.path,
      '-Log',
      _windowsLog.path,
      '-Exe',
      Platform.resolvedExecutable,
    ], mode: ProcessStartMode.detached);
    exit(0);
  }
  // The Mac app is sandboxed and can't replace itself, so unpack the new one into Downloads and show it.
  final downloads = await getDownloadsDirectory();
  if (downloads == null) throw const FileSystemException('No Downloads folder');
  final target = Directory('${downloads.path}/Dremio $version');
  if (await target.exists()) await target.delete(recursive: true);
  await target.create(recursive: true);
  final unzip = await Process.run('/usr/bin/ditto', ['-x', '-k', file.path, target.path]);
  if (unzip.exitCode != 0) throw const FileSystemException('Couldn’t unpack the update');
  await file.delete();
  await Process.run('/usr/bin/open', ['-R', '${target.path}/Dremio.app']);
  return 'Dremio $version is in Downloads. Quit Dremio and drag the new app into Applications to replace it.';
}

/// Written by the Windows update script when it fails; read and cleared by [lastUpdateFailure].
File get _windowsLog => File('${Directory.systemTemp.path}/dremio-update.log');

/// Why the last Windows update didn't finish, if it didn't.
Future<String?> lastUpdateFailure() async {
  if (!Platform.isWindows) return null;
  try {
    final log = _windowsLog;
    if (!await log.exists()) return null;
    final reason = (await log.readAsString()).trim();
    await log.delete();
    return reason.isEmpty ? 'unknown error' : reason;
  } catch (_) {
    return null;
  }
}

// Always relaunches Dremio, old or new. Files can stay locked for a moment after exit, so copying retries.
const _windowsScript = r'''
param([int]$ProcessId, [string]$Zip, [string]$Target, [string]$Exe, [string]$Log)
$ErrorActionPreference = 'Stop'
try {
  Wait-Process -Id $ProcessId -Timeout 30 -ErrorAction SilentlyContinue
  $staging = Join-Path ([IO.Path]::GetTempPath()) ('dremio-update-' + [guid]::NewGuid())
  Expand-Archive -LiteralPath $Zip -DestinationPath $staging -Force
  $copied = $false
  for ($i = 0; $i -lt 20 -and -not $copied; $i++) {
    try {
      Copy-Item -Path (Join-Path $staging '*') -Destination $Target -Recurse -Force
      $copied = $true
    } catch {
      $last = $_
      Start-Sleep -Milliseconds 500
    }
  }
  if (-not $copied) { throw $last }
  Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $Zip -Force -ErrorAction SilentlyContinue
} catch {
  "$($_.Exception.Message)" | Out-File -FilePath $Log -Encoding utf8
} finally {
  Start-Process -FilePath $Exe
}
''';
