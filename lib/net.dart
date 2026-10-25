import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const userAgent = 'Dremio/0.4 Desktop';
final _client = http.Client();

Future<dynamic> getJson(String url, {Duration timeout = const Duration(seconds: 15)}) async {
  final response = await _client.get(Uri.parse(url), headers: {'User-Agent': userAgent}).timeout(timeout);
  if (response.statusCode != 200) throw http.ClientException('HTTP ${response.statusCode}', Uri.parse(url));
  if (response.bodyBytes.length > 8 * 1024 * 1024) throw http.ClientException('Response too large', Uri.parse(url));
  return jsonDecode(utf8.decode(response.bodyBytes));
}

/// Some home networks reset TLS handshakes over IPv6 (large post-quantum
/// ClientHellos hitting a broken path MTU), so try IPv4 first and fall back.
class PreferIPv4 extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionFactory = (uri, proxyHost, proxyPort) async {
      if (proxyHost != null) return Socket.startConnect(proxyHost, proxyPort!);
      final secure = uri.scheme == 'https';
      final port = uri.hasPort ? uri.port : (secure ? 443 : 80);
      var cancelled = false;
      ConnectionTask<Socket>? current;

      Future<Socket> connect() async {
        final addresses = await InternetAddress.lookup(uri.host);
        int order(InternetAddress a) => a.type == InternetAddressType.IPv4 ? 0 : 1;
        addresses.sort((a, b) => order(a) - order(b));
        Object? failure;
        for (final address in addresses) {
          if (cancelled) break;
          try {
            final task = secure ? await SecureSocket.startConnect(address, port, context: context) : await Socket.startConnect(address, port);
            current = task;
            return await task.socket.timeout(
              const Duration(seconds: 6),
              onTimeout: () {
                task.cancel();
                throw SocketException('Timed out connecting to ${uri.host}');
              },
            );
          } catch (error) {
            failure = error;
          }
        }
        throw failure ?? SocketException('No address for ${uri.host}');
      }

      return ConnectionTask.fromSocket(connect(), () {
        cancelled = true;
        current?.cancel();
      });
    };
    return client;
  }
}
