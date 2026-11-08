import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/settings/secure.dart';
import 'package:karots_suite_onboard/shelf/account.dart';
import 'package:karots_suite_onboard/suite/client.dart';

import 'fake_shop.dart';

void main() {
  late FakeShop shop;
  setUp(() async {
    shop = FakeShop();
    await shop.start();
  });
  tearDown(() => shop.server.close(force: true));

  Object? fail(dynamic r, int status, String code, String msg) {
    r.response.statusCode = status;
    return {
      'error': {'code': code, 'message': msg},
    };
  }

  test('signs in as the person, saying it is Karots Shelf', () async {
    shop.routes['POST /api/v1/auth/login'] = (r, body) {
      r.response.headers.add('set-cookie', 'pos_token=abc; Path=/');
      return {
        'user': {'id': 7, 'name': 'Nimali', 'role': 'cashier'},
      };
    };
    shop.routes['GET /api/v1/me'] = (r, _) => {'shopName': 'Iman', 'mustChangePin': false};
    final c = SuiteClient(shop.url, app: 'shelf', device: 'phone-1');
    final u = await c.signInPerson('0771111111', '1234');
    expect(u.name, 'Nimali');
    expect(u.role, 'cashier');
    final (_, _, h, body) = shop.calls.first;
    expect(jsonDecode(body), {'phone': '0771111111', 'pin': '1234', 'app': 'shelf', 'deviceLabel': 'Karots Shelf'});
    expect(h['x-ks-app'], 'shelf');
    expect(h['x-ks-device'], 'karots-shelf-phone-1');
    await c.get('/me');
    expect(shop.calls.last.$3['cookie'], 'pos_token=abc');
  });

  test('each refusal says what to do', () async {
    final c = SuiteClient(shop.url, app: 'shelf', device: 'p');
    Future<String> msg() async {
      try {
        await c.signInPerson('0771111111', '1234');
        return 'signed in';
      } on SuiteError catch (e) {
        return e.message;
      }
    }

    shop.routes['POST /api/v1/auth/login'] = (r, _) => fail(r, 401, 'UNAUTHORIZED', 'invalid credentials');
    expect(await msg(), 'Wrong phone number or PIN');
    shop.routes['POST /api/v1/auth/login'] = (r, _) => fail(r, 403, 'SHELF_NO_ACCESS', 'x');
    expect(await msg(), 'Ask the owner to give you Karots Shelf (Users page)');
    shop.routes['POST /api/v1/auth/login'] = (r, _) {
      r.response.headers.add('set-cookie', 'pos_token=abc; Path=/');
      return {
        'user': {'id': 7, 'name': 'N', 'role': 'cashier'},
      };
    };
    shop.routes['GET /api/v1/me'] = (r, _) => {'mustChangePin': true};
    expect(await msg(), "Change your PIN on the shop's PC first");
  });

  test('the PIN is kept only as a salted hash', () async {
    final a = await ShelfAccount.make(address: 'http://x', phone: '077', name: 'N', role: 'cashier', pin: '1234');
    final b = await ShelfAccount.make(address: 'http://x', phone: '077', name: 'N', role: 'cashier', pin: '1234');
    expect(a.pinHash, isNot(b.pinHash));
    expect(a.toJson().values.contains('1234'), isFalse);
    expect(await a.checkPin('1234'), isTrue);
    expect(await a.checkPin('4321'), isFalse);
    final store = MemoryStore();
    await ShelfAccounts(store).save(a);
    final back = (await ShelfAccounts(store).find('077'))!;
    expect(await back.checkPin('1234'), isTrue);
    expect(await ShelfAccounts(store).current(), isNull);
    await ShelfAccounts(store).setCurrent('077');
    expect((await ShelfAccounts(store).current())!.name, 'N');
  });
}
