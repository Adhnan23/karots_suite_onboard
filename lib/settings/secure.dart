import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Small secrets: the app PIN's hash and the support secret.
abstract class KeyStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class SecureStore implements KeyStore {
  static const _s = FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);
}

class MemoryStore implements KeyStore {
  final _m = <String, String>{};
  @override
  Future<String?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, String value) async => _m[key] = value;
}

const supportSecretKey = 'support_secret';
