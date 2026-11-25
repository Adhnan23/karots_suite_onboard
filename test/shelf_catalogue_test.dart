import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/data/db.dart';
import 'package:karots_suite_onboard/data/models.dart';
import 'package:karots_suite_onboard/shelf/catalogue_pick.dart';
import 'package:karots_suite_onboard/suite/client.dart';
import 'package:karots_suite_onboard/sync/push.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fake_shop.dart';

// CTL-13 (the suite's docs/rules/plugins/catalogue.md): Karots Shelf's From catalogue.
void main() {
  sqfliteFfiInit();
  Shop shopWith() => Shop(
    name: 'Iman',
    kind: 'pharmacy',
    address: '',
    snapshot: {
      'plugins': ['productplus', 'catalogue'],
      'stockTake': true,
      'units': [
        {'id': 4, 'abbreviation': 'pcs', 'isDefault': true},
        {'id': 7, 'abbreviation': 'tab'},
      ],
      'fields': [
        {'id': 1, 'key': 'generic', 'label': 'Generic Name', 'isActive': true},
      ],
    },
  );
  final pick = {
    'id': 303,
    'name': 'Amlodipine 5mg (Cadila)',
    'unit': 'tab',
    'unitId': 7,
    'fields': {'Generic Name': 'Amlodipine', 'Company': 'Cadila'},
    'sections': {
      'productplus': {
        'values': {'generic': 'Amlodipine', 'gone_field': 'x'},
      },
    },
  };

  test('a pick fills the name, the shop\'s unit and its own fields, keeps the category, and carries the item', () {
    final d = draftFromShopPick(shopWith(), pick, category: 'Medicine');
    expect(d.product.name, 'Amlodipine 5mg (Cadila)');
    expect(d.product.unit, 'tab');
    expect(d.product.category, 'Medicine');
    expect(d.product.fields, {'Generic Name': 'Amlodipine'}, reason: 'only the fields the shop has');
    expect(d.product.cost, '', reason: 'never a price');
    expect(d.catalogueItem, 303);
  });

  test('a unit the shop has not matched: the shop\'s default', () {
    final d = draftFromShopPick(shopWith(), {...pick, 'unitId': 0});
    expect(d.product.unit, 'pcs');
  });

  test('a pick saved offline keeps its item in the queue', () {
    final d = draftFromShopPick(shopWith(), pick);
    expect(Draft.fromJson(jsonDecode(jsonEncode(d.toJson())) as Map).catalogueItem, 303);
  });

  group('made in the shop', () {
    late FakeShop shop;
    late Db db;
    late Shop s;
    var gone = false;
    setUp(() async {
      shop = FakeShop();
      await shop.start();
      db = await Db.openWith(path: inMemoryDatabasePath, factory: databaseFactoryFfi);
      s = shopWith()..address = shop.url;
      gone = false;
      shop.routes = {
        'POST /api/v1/admin/categories/quick': (_, _) => {'id': 10},
        'POST /api/v1/admin/inventory/intake/create': (r, body) {
          final extra = ((jsonDecode(body) as Map)['product'] as Map)['extra'] as Map?;
          if (gone && extra?['catalogue'] != null) {
            r.response.statusCode = 422;
            return {
              'error': {'code': 'VALIDATION', 'message': "that catalogue product isn't on this PC"},
            };
          }
          return {'productId': 70, 'name': 'Amlodipine'};
        },
      };
    });
    tearDown(() async {
      await shop.server.close(force: true);
      await db.close();
    });
    List<Map> creates() => [
      for (final c in shop.calls)
        if (c.$2 == '/api/v1/admin/inventory/intake/create') ((jsonDecode(c.$4) as Map)['product'] as Map)['extra'] as Map,
    ];

    test('the product is linked to its catalogue item, with the shop\'s fields', () async {
      final r = await pushCreate(db, SuiteClient(shop.url), s, draftFromShopPick(s, pick));
      expect(r.productId, 70);
      expect(creates().single, {
        'productplus': {
          'values': {'generic': 'Amlodipine'},
        },
        'catalogue': {'itemId': 303},
      });
    });

    test('the item left the copy before it got there: made without the link, never refused', () async {
      gone = true;
      final r = await pushCreate(db, SuiteClient(shop.url), s, draftFromShopPick(s, pick));
      expect(r.productId, 70);
      expect(creates().length, 2);
      expect(creates().last.containsKey('catalogue'), isFalse);
    });
  });
}
