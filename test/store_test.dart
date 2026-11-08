import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/settings/secure.dart';

class _Broken implements KeyStore {
  @override
  Future<String?> read(String key) async => throw Exception('no keyring');
  @override
  Future<void> write(String key, String value) async => throw Exception('no keyring');
}

void main() {
  test('no keyring: values go to a private file instead, and come back', () async {
    final dir = Directory.systemTemp.createTempSync('ks');
    final s = FallbackStore(_Broken(), FileStore('${dir.path}/store.json'));
    await s.write('support_secrets', '[{"name":"Main"}]');
    expect(await s.read('support_secrets'), '[{"name":"Main"}]');
    expect(await FileStore('${dir.path}/store.json').read('support_secrets'), '[{"name":"Main"}]');
    if (!Platform.isWindows) {
      expect((await File('${dir.path}/store.json').stat()).modeString(), 'rw-------');
    }
  });

  test('with a keyring, the file is never used', () async {
    final dir = Directory.systemTemp.createTempSync('ks');
    final s = FallbackStore(MemoryStore(), FileStore('${dir.path}/store.json'));
    await s.write('a', 'b');
    expect(await s.read('a'), 'b');
    expect(File('${dir.path}/store.json').existsSync(), isFalse);
  });
}
