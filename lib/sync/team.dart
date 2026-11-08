import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../data/db.dart';
import 'device_sync.dart';

const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/// A new team key: KT-XXXX-XXXX-XXXX (no 0/O or 1/I to misread).
String newTeamKey() {
  final r = Random.secure();
  String part() => List.generate(4, (_) => _alphabet[r.nextInt(_alphabet.length)]).join();
  return 'KT-${part()}-${part()}-${part()}';
}

String _norm(String key) => key.trim().toUpperCase();

/// What devices announce instead of the key: a one-way fingerprint of it.
String teamPrint(String key) => sha256.convert(utf8.encode('karots-onboard-team|${_norm(key)}')).toString().substring(0, 16);

const announcePort = 8766;

String announce(String device, String print, int port) => 'karots-onboard|1|$device|$print|$port';

/// Another device of this team, from its announcement; null for anything else.
({String device, int port})? readAnnounce(String msg, {required String myDevice, required String myPrint}) {
  final p = msg.split('|');
  if (p.length != 5 || p[0] != 'karots-onboard' || p[1] != '1' || p[2] == myDevice || p[3] != myPrint) return null;
  final port = int.tryParse(p[4]);
  return port == null ? null : (device: p[2], port: port);
}

class Peer {
  Peer(this.device, this.address, this.port);
  final String device;
  String address;
  int port;
  DateTime? lastSync;
  String error = '';
}

/// Keeps this device the same as the team's others on the same Wi-Fi while the
/// app is open: it answers them (with the key), announces itself, and syncs with
/// every team device it hears of every 2 minutes and soon after a change here.
class TeamSync extends ChangeNotifier {
  TeamSync(
    this.db, {
    required String key,
    required this.device,
    this.port = SyncHost.defaultPort,
    this.discover = true,
    this.every = const Duration(minutes: 2),
  }) : key = _norm(key);
  final Db db;
  final String key, device;
  final bool discover;
  final Duration every;
  int port;
  SyncHost? _host;
  RawDatagramSocket? _udp;
  final _timers = <Timer>[];
  Timer? _soon;
  final _peers = <String, Peer>{};
  bool syncing = false;
  List<Peer> get peers => _peers.values.toList();

  Future<void> start() async {
    final h = await SyncHost.start(db, port: port, code: key, maxWrong: null); // a 12-character key can't be guessed
    _host = h;
    port = h.port;
    if (discover) {
      try {
        final u = await RawDatagramSocket.bind(InternetAddress.anyIPv4, announcePort, reuseAddress: true);
        u.broadcastEnabled = true;
        u.listen((e) {
          if (e != RawSocketEvent.read) return;
          final d = u.receive();
          if (d == null) return;
          final a = readAnnounce(utf8.decode(d.data, allowMalformed: true), myDevice: device, myPrint: teamPrint(key));
          if (a != null) addPeer(a.device, d.address.address, a.port);
        });
        _udp = u;
        void say() => u.send(utf8.encode(announce(device, teamPrint(key), port)), InternetAddress('255.255.255.255'), announcePort);
        say();
        _timers.add(Timer.periodic(const Duration(seconds: 20), (_) => say()));
      } catch (_) {
        // no broadcast on this network: devices can still be added by address
      }
    }
    _timers.add(Timer.periodic(every, (_) => syncNow()));
  }

  bool _stopped = false;

  Future<void> stop() async {
    _stopped = true;
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    _soon?.cancel();
    _udp?.close();
    await _host?.stop();
  }

  void addPeer(String id, String address, int port) {
    final known = _peers[id];
    if (known != null) {
      known
        ..address = address
        ..port = port;
      return;
    }
    _peers[id] = Peer(id, address, port);
    notifyListeners();
    syncNow();
  }

  /// A change here: sync in a few seconds (several changes, one sync).
  void soon() {
    if (_stopped) return;
    _soon?.cancel();
    _soon = Timer(const Duration(seconds: 10), syncNow);
  }

  Future<void>? _running;

  /// Syncs with every team device now; while one runs, waits for it instead.
  Future<void> syncNow() => _stopped ? Future.value() : _running ??= _sync().whenComplete(() => _running = null);

  Future<void> _sync() async {
    syncing = true;
    notifyListeners();
    for (final p in peers) {
      try {
        await syncWith(db, '${p.address}:${p.port}', key);
        p
          ..lastSync = DateTime.now()
          ..error = '';
      } on SyncError catch (e) {
        p.error = e.message.startsWith('Wrong code') ? 'That device is in another team' : e.message;
      } catch (e) {
        p.error = 'Not reachable';
      }
    }
    syncing = false;
    notifyListeners();
  }
}
