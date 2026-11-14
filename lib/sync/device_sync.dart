import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/backup.dart';
import '../data/db.dart';

export '../data/backup.dart' show SyncStep;

String _mb(int bytes) => (bytes / 1e6).toStringAsFixed(1);

/// Sends bytes in pieces, saying how far ('Sending 8.0 of 30.1 MB').
Stream<List<int>> _sending(List<int> bytes, ValueNotifier<SyncStep?>? step) async* {
  const piece = 256 * 1024;
  for (var i = 0; i < bytes.length; i += piece) {
    final end = min(i + piece, bytes.length);
    step?.value = (text: 'Sending ${_mb(end)} of ${_mb(bytes.length)} MB', part: end / bytes.length);
    yield bytes.sublist(i, end);
  }
}

/// Reads a body in, saying how far ('Receiving 12.3 of 30.1 MB'; no total: just MB).
Future<String> _receiving(Stream<List<int>> body, int? total, ValueNotifier<SyncStep?>? step) async {
  final got = BytesBuilder(copy: false);
  void say() => step?.value = total == null || total <= 0
      ? (text: 'Receiving ${_mb(got.length)} MB', part: null)
      : (text: 'Receiving ${_mb(got.length)} of ${_mb(total)} MB', part: got.length / total);
  say();
  await for (final c in body) {
    got.add(c);
    say();
  }
  return utf8.decode(got.takeBytes());
}

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
  SyncHost._(this._server, this.code, this.maxWrong, this.step) : port = _server.port;

  /// What it's doing for the other device now (null: waiting).
  final ValueNotifier<SyncStep?> step;
  final HttpServer _server;

  /// The port it listened on (kept: the server forgets it once closed).
  final int port;
  final String code;

  /// Wrong codes allowed before it closes (null: none counted, for the team's long key).
  final int? maxWrong;
  int _wrong = 0;
  bool closed = false;
  static const defaultPort = 8765;

  static Future<SyncHost> start(Db db, {int port = defaultPort, String? code, int? maxWrong = 5, ValueNotifier<SyncStep?>? step}) async {
    final s = await HttpServer.bind(InternetAddress.anyIPv4, port);
    final h = SyncHost._(s, code ?? newSyncCode(), maxWrong, step ?? ValueNotifier(null));
    final say = h.step;
    s.listen((r) async {
      try {
        if (r.headers.value('x-sync-code') != h.code) {
          r.response.statusCode = 403;
          // A short code can be guessed: after a few wrong ones, stop answering.
          if (h.maxWrong != null && ++h._wrong >= h.maxWrong!) {
            await r.response.close();
            await h.stop();
            return;
          }
        } else if (r.method == 'GET' && r.uri.path == '/backup') {
          say.value = (text: 'Reading this device\'s catalogue…', part: null);
          final bytes = utf8.encode(await exportBackup(db, since: r.uri.queryParameters['since']));
          r.response.headers.contentType = ContentType.json;
          r.response.contentLength = bytes.length;
          await r.response.addStream(_sending(bytes, say));
        } else if (r.method == 'POST' && r.uri.path == '/backup') {
          final got = await importBackup(db, await _receiving(r, r.contentLength, say), step: say);
          r.response.headers.contentType = ContentType.json;
          r.response.write(jsonEncode({'products': got.products, 'suppliers': got.suppliers, 'shops': got.shops}));
        } else {
          r.response.statusCode = 404;
        }
      } catch (e) {
        r.response.statusCode = 500;
        r.response.write('$e');
      } finally {
        say.value = null;
      }
      await r.response.close();
    });
    return h;
  }

  Future<void> stop() async {
    closed = true;
    await _server.close(force: true);
  }

  /// This device's addresses on the local network, for the other one to type.
  static Future<List<String>> addresses() async => [
    for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4))
      for (final a in i.addresses)
        if (!a.isLoopback && !i.name.startsWith('docker') && !i.name.startsWith('br-') && !i.name.startsWith('virbr')) a.address,
  ];
}

/// How far two devices are in step: the other's 'changes' mark on what we took
/// (its clock), and ours on what we sent (our clock). Null: send everything.
typedef SyncMarks = ({String? got, String? sent});

class SyncResult {
  SyncResult(this.got, this.sent, this.marks);
  final ImportResult got, sent;
  final SyncMarks marks;

  /// Products in what the other device sent (all of them, or only its changes).
  int get received => got.received;
}

/// Swaps with the device at base (http://ip:port): takes its backup in, sends
/// ours. With since (the last result's marks) only what changed travels; an
/// older app ignores it and sends everything, which merges the same.
Future<SyncResult> syncWith(Db db, String base, String code, {SyncMarks? since, ValueNotifier<SyncStep?>? step}) async {
  try {
    return await _syncWith(db, base, code, since, step);
  } finally {
    step?.value = null;
  }
}

Future<SyncResult> _syncWith(Db db, String base, String code, SyncMarks? since, ValueNotifier<SyncStep?>? step) async {
  final url = base.contains('://') ? base : 'http://$base';
  final b = Uri.parse(url.endsWith('/') ? url.substring(0, url.length - 1) : url);
  final headers = {'x-sync-code': code.trim()};
  final sentMark = Db.stamp(); // what changes after this goes next time
  step?.value = (text: 'Reading this device\'s catalogue…', part: null);
  final mine = utf8.encode(await exportBackup(db, since: since?.sent));
  final client = http.Client();
  try {
    step?.value = (text: 'Waiting for the other device…', part: null);
    final res = await client
        .send(http.Request('GET', b.replace(path: '/backup', queryParameters: {if (since?.got != null) 'since': since!.got}))..headers.addAll(headers))
        .timeout(const Duration(minutes: 5));
    if (res.statusCode == 403) throw SyncError('Wrong code: check the 6 digits on the other device');
    if (res.statusCode != 200) throw SyncError('The other device answered ${res.statusCode}');
    final text = await _receiving(res.stream, res.contentLength, step).timeout(const Duration(minutes: 10)); // a whole catalogue is ~30 MB
    final got = await importBackup(db, text, step: step);
    final post = http.StreamedRequest('POST', b.replace(path: '/backup'))
      ..headers.addAll({...headers, 'content-type': 'application/json'})
      ..contentLength = mine.length;
    final going = client.send(post);
    await post.sink.addStream(_sending(mine, step));
    await post.sink.close();
    step?.value = (text: 'The other device is saving it…', part: null);
    final sent = await http.Response.fromStream(await going.timeout(const Duration(minutes: 10))); // it saves it all before answering
    if (sent.statusCode != 200) throw SyncError('The other device couldn\'t take ours (${sent.statusCode})');
    final m = jsonDecode(sent.body) as Map;
    return SyncResult(got, ImportResult(m['products'] as int, m['suppliers'] as int, m['shops'] as int), (got: got.changes ?? since?.got, sent: sentMark));
  } finally {
    client.close();
  }
}
