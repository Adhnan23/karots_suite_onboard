import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/suite/client.dart';
import 'package:karots_suite_onboard/suite/support_pin.dart';

import 'fake_shop.dart';

void main() {
  late FakeShop shop;
  setUp(() async => (shop = FakeShop()).start());
  tearDown(() => shop.server.close(force: true));

  test('signs in as the system user, keeps the cookie, sends the device header', () async {
    final now = DateTime.now();
    final pins = supportPinsNow('sec', 'AB12CD34', now);
    shop.routes = {
      'GET /api/v1/auth/login-info': (_, _) => {'installId': 'AB12CD34', 'shopName': 'Iman'},
      'POST /api/v1/auth/login': (r, body) {
        final b = jsonDecode(body) as Map;
        if (b['pin'] != pins[1]) {
          r.response.statusCode = 401;
          return {
            'error': {'code': 'UNAUTHORIZED', 'message': 'wrong PIN'},
          };
        }
        r.response.headers.add('set-cookie', 'pos_token=tok123; Path=/; HttpOnly; SameSite=Strict');
        return {
          'user': {'id': 1},
        };
      },
      'GET /api/v1/me': (_, _) => {
        'shopName': 'Iman',
        'plugins': ['productplus'],
        'stockTakeEnabled': true,
      },
    };
    final c = SuiteClient(shop.url);
    final info = await c.loginInfo();
    expect(info.installId, 'AB12CD34');
    await c.signIn('sec', info.installId, now: now); // this hour's PIN refused, the last hour's taken
    final me = await c.me();
    expect(me.plugins, ['productplus']);
    expect(me.stockTakeEnabled, isTrue);
    final login = shop.calls.where((x) => x.$2 == '/api/v1/auth/login').map((x) => jsonDecode(x.$4)['phone']).toSet();
    expect(login, {'0000000001'});
    final last = shop.calls.last;
    expect(last.$3['cookie'], contains('pos_token=tok123'));
    expect(last.$3['x-ks-device'], 'karots-suite-onboard');
  });

  test('an error body becomes a SuiteError with its message', () async {
    shop.routes = {
      'POST /api/v1/admin/inventory/intake/create': (r, _) {
        r.response.statusCode = 409;
        return {
          'error': {'code': 'CONFLICT', 'message': '“Panadol” already exists'},
        };
      },
    };
    final c = SuiteClient(shop.url);
    await expectLater(
      c.intakeCreate({'name': 'Panadol'}, quantity: '5', expiry: ''),
      throwsA(isA<SuiteError>().having((e) => e.message, 'message', '“Panadol” already exists').having((e) => e.status, 'status', 409)),
    );
  });

  test('the whole-shop reads', () async {
    shop.routes = {
      'GET /api/v1/admin/products/export': (r, _) => 'name,barcode\nA,1\n',
      'GET /api/v1/admin/products/packs': (_, _) => {
        '7': [
          {
            'name': 'Card',
            'size': '10',
            'sellingPrice': '95.00',
            'wholesalePrice': '0.00',
            'barcodes': ['C7'],
          },
        ],
      },
    };
    final c = SuiteClient(shop.url);
    expect(await c.productsCsv(customFields: true), 'name,barcode\nA,1\n');
    expect(shop.calls.last.$2, '/api/v1/admin/products/export');
    final packs = await c.allPacks();
    expect(packs[7]!.single['name'], 'Card');
  });

  test('a dev build with no seed takes the dev PIN 2273, tried last', () async {
    shop.routes = {
      'POST /api/v1/auth/login': (r, body) {
        if ((jsonDecode(body) as Map)['pin'] != '2273') {
          r.response.statusCode = 401;
          return {'error': {'code': 'UNAUTHORIZED', 'message': 'wrong PIN'}};
        }
        return {'user': {'id': 1}};
      },
    };
    await SuiteClient(shop.url).signIn('sec', 'AB12CD34');
    expect([for (final c in shop.calls) jsonDecode(c.$4)['pin']].last, '2273');
  });
}
