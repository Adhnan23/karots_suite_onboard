import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/settings/secure.dart';
import 'package:karots_suite_onboard/shelf/account.dart';
import 'package:karots_suite_onboard/shelf/lock_screen.dart';
import 'package:karots_suite_onboard/theme/app_theme.dart';

void main() {
  testWidgets('the PIN opens it offline; 5 wrong and only a sign-in will; Someone else signs in', (t) async {
    final accounts = ShelfAccounts(MemoryStore());
    final a = (await t.runAsync(() => ShelfAccount.make(address: 'http://shop', phone: '0771111111', name: 'Nimali', role: 'cashier', pin: '1234')))!;
    String? opened;
    String? signIn;
    Future<void> show() async {
      await t.pumpWidget(
        MaterialApp(
          theme: ksTheme(Brightness.light, fonts: false),
          home: ShelfLockScreen(account: a, accounts: accounts, onOpen: (pin) => opened = pin, onSignIn: ({phone}) => signIn = phone ?? 'someone'),
        ),
      );
    }

    Future<void> type(String pin) async {
      await t.enterText(find.byType(TextField), pin);
      await t.tap(find.text('Open'));
      // The PIN's hash takes real time: run until the button is back (or it opened).
      for (var i = 0; i < 100; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await t.pump(const Duration(milliseconds: 20));
        final b = find.widgetWithText(FilledButton, 'Open');
        if (opened != null || b.evaluate().isEmpty || t.widget<FilledButton>(b).onPressed != null) break;
      }
    }

    await show();
    expect(find.text('Nimali · 0771111111'), findsOneWidget);
    await type('9999');
    expect(find.text('Wrong PIN'), findsOneWidget);
    await type('1234');
    expect(opened, '1234');
    expect(a.wrongTries, 0);

    opened = null;
    for (var i = 0; i < ShelfAccount.maxWrong; i++) {
      await type('9999');
    }
    expect(find.text('Too many wrong PINs: sign in again with the shop in reach.'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await t.tap(find.text('Sign in again'));
    expect(signIn, '0771111111');
    expect((await t.runAsync(() => accounts.find('0771111111')))!.lockedOut, isTrue);

    await t.tap(find.text('Someone else'));
    expect(signIn, 'someone');
    expect(opened, isNull);
  });
}
