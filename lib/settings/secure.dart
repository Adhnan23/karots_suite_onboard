import 'dart:convert';
import 'dart:io';

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

/// A JSON file only this user can read (chmod 600): where secrets go when the
/// system has no keyring (a Linux desktop without one).
class FileStore implements KeyStore {
  FileStore(this.path);
  final String path;

  Future<Map<String, dynamic>> _all() async {
    final f = File(path);
    if (!await f.exists()) return {};
    return (jsonDecode(await f.readAsString()) as Map).cast<String, dynamic>();
  }

  @override
  Future<String?> read(String key) async => (await _all())[key] as String?;

  @override
  Future<void> write(String key, String value) async {
    final m = await _all()
      ..[key] = value;
    final f = File(path);
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode(m));
    if (!Platform.isWindows) await Process.run('chmod', ['600', path]);
  }
}

/// The keyring when there is one; otherwise the private file.
class FallbackStore implements KeyStore {
  FallbackStore(this.primary, this.file);
  final KeyStore primary;
  final FileStore file;
  bool _useFile = false;

  @override
  Future<String?> read(String key) async {
    if (!_useFile) {
      try {
        return await primary.read(key);
      } catch (_) {
        _useFile = true;
      }
    }
    return file.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    if (!_useFile) {
      try {
        return await primary.write(key, value);
      } catch (_) {
        _useFile = true;
      }
    }
    return file.write(key, value);
  }
}
