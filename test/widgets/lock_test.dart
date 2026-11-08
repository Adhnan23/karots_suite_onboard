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
    await t.pumpWidget(MaterialApp(theme: ksTheme(Brightness.light, fonts: false), home: LockScreen(store: MemoryStore(), onOpen: () => opened = true)));
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
}
