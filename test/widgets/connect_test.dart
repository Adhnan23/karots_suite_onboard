import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/data/models.dart';
import 'package:karots_suite_onboard/screens/connect_sheet.dart';
import 'package:karots_suite_onboard/theme/app_theme.dart';

void main() {
  test('Tailscale addresses are told apart from shop Wi-Fi', () {
    expect(Shop(name: 'a', address: 'http://100.101.5.2:3000').viaTailscale, isTrue);
    expect(Shop(name: 'a', address: 'http://iman-main.tail1234.ts.net:3000').viaTailscale, isTrue);
    expect(Shop(name: 'a', address: 'http://192.168.1.20:3000').viaTailscale, isFalse);
  });

  Future<void> show(WidgetTester t, Shop s) => t.pumpWidget(
    MaterialApp(
      theme: ksTheme(Brightness.light, fonts: false),
      home: Scaffold(body: ConnectInfo(shop: s)),
    ),
  );

  testWidgets('on shop Wi-Fi the sign-in is said to be unencrypted', (t) async {
    await show(t, Shop(name: 'Iman', address: 'http://192.168.1.20:3000'));
    expect(find.textContaining('not encrypted'), findsOneWidget);
    await show(t, Shop(name: 'Iman', address: 'http://100.101.5.2:3000'));
    expect(find.textContaining('not encrypted'), findsNothing);
    expect(find.textContaining('Tailscale'), findsOneWidget);
  });
}
