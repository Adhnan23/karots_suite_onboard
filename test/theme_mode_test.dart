import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/settings/secure.dart';
import 'package:karots_suite_onboard/theme/mode.dart';

void main() {
  test('System → Light → Dark → System, remembered on the device', () async {
    final store = MemoryStore();
    final m = ModeController(store);
    await m.load();
    expect(m.value, ThemeMode.system);
    await m.next();
    expect(m.value, ThemeMode.light);
    await m.next();
    expect(m.value, ThemeMode.dark);
    final again = ModeController(store);
    await again.load();
    expect(again.value, ThemeMode.dark);
    await again.next();
    expect(again.value, ThemeMode.system);
  });
}
