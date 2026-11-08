import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../data/backup.dart';
import '../data/db.dart';

class SyncError implements Exception {
  SyncError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A new 6-digit code for one sync screen.
String newSyncCode() => (Random.secure().nextInt(900000) + 100000).toString();

/// This device, open to another on the same network while the screen is open:
/// it hands its backup out and merges one in, only with the code.
class SyncHost {
  SyncHost._(this._server, this.code);
  final HttpServer _server;
  final String code;
  int get port => _server.port;
  static const defaultPort = 8765;

  static Future<SyncHost> start(Db db, {int port = defaultPort, String? code}) async {
    final s = await HttpServer.bind(InternetAddress.anyIPv4, port);
    final h = SyncHost._(s, code ?? newSyncCode());
    s.listen((r) async {
      try {
        if (r.headers.value('x-sync-code') != h.code) {
          r.response.statusCode = 403;
        } else if (r.method == 'GET' && r.uri.path == '/backup') {
          r.response.headers.contentType = ContentType.json;
          r.response.write(await exportBackup(db));
        } else if (r.method == 'POST' && r.uri.path == '/backup') {
          final got = await importBackup(db, await utf8.decodeStream(r));
          r.response.headers.contentType = ContentType.json;
          r.response.write(jsonEncode({'products': got.products, 'suppliers': got.suppliers, 'shops': got.shops}));
        } else {
          r.response.statusCode = 404;
        }
      } catch (e) {
        r.response.statusCode = 500;
        r.response.write('$e');
      }
      await r.response.close();
    });
    return h;
  }

  Future<void> stop() => _server.close(force: true);

  /// This device's addresses on the local network, for the other one to type.
  static Future<List<String>> addresses() async => [
    for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4))
      for (final a in i.addresses)
        if (!a.isLoopback && !i.name.startsWith('docker') && !i.name.startsWith('br-') && !i.name.startsWith('virbr')) a.address,
  ];
}

class SyncResult {
  SyncResult(this.got, this.sent);
  final ImportResult got, sent;
}

/// Swaps with the device at base (http://ip:port): takes its backup in, sends ours.
Future<SyncResult> syncWith(Db db, String base, String code) async {
  final url = base.contains('://') ? base : 'http://$base';
  final b = Uri.parse(url.endsWith('/') ? url.substring(0, url.length - 1) : url);
  final headers = {'x-sync-code': code.trim()};
  final mine = await exportBackup(db);
  final res = await http.get(b.replace(path: '/backup'), headers: headers).timeout(const Duration(seconds: 30));
  if (res.statusCode == 403) throw SyncError('Wrong code: check the 6 digits on the other device');
  if (res.statusCode != 200) throw SyncError('The other device answered ${res.statusCode}');
  final got = await importBackup(db, utf8.decode(res.bodyBytes));
  final sent = await http
      .post(
        b.replace(path: '/backup'),
        headers: {...headers, 'content-type': 'application/json'},
        body: mine,
      )
      .timeout(const Duration(seconds: 60));
  if (sent.statusCode != 200) throw SyncError('The other device couldn\'t take ours (${sent.statusCode})');
  final m = jsonDecode(sent.body) as Map;
  return SyncResult(got, ImportResult(m['products'] as int, m['suppliers'] as int, m['shops'] as int));
}
