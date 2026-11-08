import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/suite/client.dart';
import 'package:karots_suite_onboard/sync/alternatives.dart';

import 'fake_shop.dart';

void main() {
  test('a pulled group lists its tiers and members', () {
    final g = AltGroup.fromJson({
      'id': 1,
      'name': 'Paracetamol 500',
      'tiers': [
        {
          'id': 4,
          'name': 'Tablets',
          'members': [
            {'productId': 7, 'name': 'Panadol 500mg'},
            {'productId': 9, 'name': 'Pandol 500'},
          ],
        },
      ],
    });
    expect(g.tiers.single.members.map((m) => m.name), ['Panadol 500mg', 'Pandol 500']);
  });

  test('copying a group to another shop finds its members there by name', () {
    final g = AltGroup.fromJson({
      'id': 1,
      'name': 'P',
      'tiers': [
        {
          'id': 4,
          'name': 'Tablets',
          'members': [
            {'productId': 7, 'name': 'Panadol 500mg'},
            {'productId': 9, 'name': 'Calpol 500'},
          ],
        },
      ],
    });
    final there = [
      {'remote_id': 70, 'name': 'panadol  500MG', 'barcode': ''},
      {'remote_id': 80, 'name': 'Something else', 'barcode': ''},
    ];
    final m = matchMembers(g.tiers.single, there);
    expect(m.found, [70]);
    expect(m.missing, ['Calpol 500']);
  });

  test('creating a group sends name, tier, then each member', () async {
    final shop = FakeShop();
    await shop.start();
    shop.routes = {
      'POST /api/v1/x/alternatives': (_, _) => {'id': 5, 'name': 'P', 'tiers': []},
      'POST /api/v1/x/alternatives/5/tiers': (_, _) => {
        'id': 5,
        'tiers': [
          {'id': 12, 'name': 'Tablets', 'members': []},
        ],
      },
      'POST /api/v1/x/alternatives/tiers/12/members': (_, _) => {'id': 5, 'tiers': []},
    };
    final id = await SuiteClient(shop.url).createAlternative('P', 'Tablets', [70, 71]);
    expect(id, 5);
    final members = [
      for (final c in shop.calls)
        if (c.$2.endsWith('/members')) jsonDecode(c.$4)['productId'],
    ];
    expect(members, [70, 71]);
    await shop.server.close(force: true);
  });
}
