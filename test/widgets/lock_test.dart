import 'package:convert/convert.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/lock/app_identity.dart';
import 'package:karots_suite_onboard/lock/lock_screen.dart';
import 'package:karots_suite_onboard/settings/secure.dart';
import 'package:karots_suite_onboard/suite/support_pin.dart';
import 'package:karots_suite_onboard/theme/app_theme.dart';

void main() {
  testWidgets('a fresh app asks only for this hour\'s code for its install ID', (t) async {
    var opened = false;
    await t.pumpWidget(
      MaterialApp(
        theme: ksTheme(Brightness.light, fonts: false),
        home: LockScreen(store: MemoryStore(), onOpen: () => opened = true),
      ),
    );
    expect(find.textContaining(appInstallId), findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);
    await t.enterText(find.byType(TextField), '000000');
    await t.tap(find.text('Open'));
    await t.pump();
    expect(opened, isFalse);
    expect(find.text('That isn\'t this hour\'s code'), findsOneWidget);
    await t.enterText(find.byType(TextField), pinFromSeed(hex.decode(appSeedHex), DateTime.now()));
    await t.tap(find.text('Open'));
    expect(opened, isTrue);
  });

  test('the phone\'s own unlock works for 24 hours after the code, then the code again', () {
    final at = DateTime(2026, 11, 9, 14);
    expect(phoneUnlockAllowed(null, at), isFalse, reason: 'a fresh install (or cleared storage) needs the code');
    final stamp = at.toIso8601String();
    expect(phoneUnlockAllowed(stamp, at.add(const Duration(hours: 23, minutes: 59))), isTrue);
    expect(phoneUnlockAllowed(stamp, at.add(const Duration(hours: 24))), isFalse);
    expect(phoneUnlockAllowed(stamp, at.subtract(const Duration(hours: 1))), isFalse, reason: 'a clock set back doesn\'t stretch it');
    expect(phoneUnlockAllowed('junk', at), isFalse);
  });

  testWidgets('a right code is remembered, so the phone can open it for the next 24 hours', (t) async {
    final store = MemoryStore();
    var opened = false;
    await t.pumpWidget(
      MaterialApp(
        theme: ksTheme(Brightness.light, fonts: false),
        home: LockScreen(store: store, onOpen: () => opened = true),
      ),
    );
    await t.enterText(find.byType(TextField), pinFromSeed(hex.decode(appSeedHex), DateTime.now()));
    await t.tap(find.text('Open'));
    await t.pumpAndSettle();
    expect(opened, isTrue);
    expect(phoneUnlockAllowed(await store.read(codeDayKey), DateTime.now()), isTrue);
  });
}
