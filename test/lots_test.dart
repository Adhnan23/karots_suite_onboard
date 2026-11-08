import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/suite/client.dart';
import 'package:karots_suite_onboard/sync/lots.dart';

import 'fake_shop.dart';

void main() {
  late FakeShop shop;
  setUp(() async {
    shop = FakeShop();
    await shop.start();
    shop.routes = {
      'GET /api/v1/admin/stock/lots/70': (_, _) => {
        'productId': 70,
        'name': 'Amoxil',
        'stockQty': '50',
        'sellingPrice': '25.00',
        'lots': [
          {'id': 1, 'qtyRemaining': '30', 'expiryDate': '2027-12-31', 'costPrice': '20.00', 'sellingPrice': '', 'source': 'adjust'},
          {'id': 2, 'qtyRemaining': '20', 'expiryDate': '', 'costPrice': '21.00', 'sellingPrice': '26.00', 'source': 'purchase'},
        ],
      },
      'POST /api/v1/admin/stock/adjust': (r, _) {
        r.response.statusCode = 204;
        return '';
      },
      'POST /api/v1/admin/stock/batches/2/price': (r, _) {
        r.response.statusCode = 204;
        return '';
      },
      'POST /api/v1/admin/stock/batches/2/expiry': (r, _) {
        r.response.statusCode = 204;
        return '';
      },
    };
  });
  tearDown(() => shop.server.close(force: true));
  List<Map> sent(String path) => [
    for (final c in shop.calls)
      if (c.$2 == path) jsonDecode(c.$4) as Map,
  ];

  test('a product\'s lots come back with count, expiry and prices', () async {
    final s = await productStock(SuiteClient(shop.url), 70);
    expect(s.total, '50');
    expect(s.lots.map((l) => (l.id, l.qty, l.expiry, l.cost, l.price)), [(1, '30', '2027-12-31', '20.00', ''), (2, '20', '', '21.00', '26.00')]);
  });

  test('editing a lot sends only what changed; a count is set on that lot', () async {
    final s = await productStock(SuiteClient(shop.url), 70);
    await editLot(SuiteClient(shop.url), 70, s, s.lots[1], count: '12', expiry: '2028-03-31', price: '26.00');
    expect(sent('/api/v1/admin/stock/adjust'), [
      {'productId': 70, 'newQuantity': '42', 'batchId': 2, 'note': 'Set in Karots Onboard'},
    ], reason: 'the product total that leaves this lot at 12');
    expect(sent('/api/v1/admin/stock/batches/2/expiry'), [
      {'expiry': '2028-03-31'},
    ]);
    expect(sent('/api/v1/admin/stock/batches/2/price'), isEmpty, reason: 'unchanged');
  });
}
