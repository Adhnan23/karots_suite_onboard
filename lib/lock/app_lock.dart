import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../settings/secure.dart';

/// The app opens only with the user's own PIN: it holds the support secret that
/// opens every shop. Kept as salt:sha256(salt+pin).
class AppLock {
  AppLock(this.store);
  final KeyStore store;
  static const key = 'app_pin_hash';

  Future<bool> hasPin() async => (await store.read(key)) != null;

  Future<void> setPin(String pin) async {
    final r = Random.secure();
    final salt = base64Url.encode(List.generate(16, (_) => r.nextInt(256)));
    await store.write(key, '$salt:${_hash(salt, pin)}');
  }

  Future<bool> check(String pin) async {
    final v = await store.read(key);
    if (v == null) return false;
    final i = v.indexOf(':');
    return _hash(v.substring(0, i), pin) == v.substring(i + 1);
  }

  static String _hash(String salt, String pin) => sha256.convert(utf8.encode('$salt$pin')).toString();
}
