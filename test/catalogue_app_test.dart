import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/data/models.dart';
import 'package:karots_suite_onboard/sync/catalogue_app.dart';

import 'fake_shop.dart';

// Onboard ⇄ the Catalogue app (catalogue repo docs/plans/onboard-sync.md; decisions: README "Piece 4").
void main() {
  CatalogProduct p(String name, {String selling = '', List<String> codes = const [], Map<String, String> fields = const {}, bool hand = false}) =>
      CatalogProduct(
        name: name,
        unit: 'tab',
        kinds: {'pharmacy'},
        selling: selling,
        barcode: codes.isEmpty ? '' : codes.first,
        barcodes: codes.skip(1).toList(),
        fields: {...fields},
        updatedAt: hand ? DateTime(2026, 11, 20, 9, 24, 38, 800, 476) : DateTime(2020),
      );
  Map cat(String name, {String selling = '', List<String> codes = const [], Map fields = const {}, String unit = 'tab'}) => {
    'id': 1,
    'name': name,
    'unit': unit,
    'kinds': 'pharmacy',
    'fields': fields,
    'selling': selling,
    'barcodes': codes,
  };

  test('the address: an IP gets http and the app\'s port', () {
    expect(CatalogueApp.normAddress('192.168.1.5'), 'http://192.168.1.5:7710');
    expect(CatalogueApp.normAddress('http://pc.tail1.ts.net:7799/'), 'http://pc.tail1.ts.net:7799');
  });

  test('a catalogue fix shows old → new; only what the catalogue gives counts', () {
    final mine = [
      p('Concor 2.5', fields: {'Generic Name': 'Bisoprolol', 'Shelf': 'A3'}),
    ];
    final plan = planSync(mine, {
      'Concor 2.5': cat('Concor COR 2.5mg', fields: {'Generic Name': 'Bisoprolol Fumarate'}),
    });
    expect(plan.fixes.single.changes, [
      (what: 'Name', mine: 'Concor 2.5', theirs: 'Concor COR 2.5mg'),
      (what: 'Generic Name', mine: 'Bisoprolol', theirs: 'Bisoprolol Fumarate'),
    ]);
    takeFix(plan.fixes.single);
    expect(mine.single.name, 'Concor COR 2.5mg');
    expect(mine.single.fields, {'Generic Name': 'Bisoprolol Fumarate', 'Shelf': 'A3'}, reason: 'a field the catalogue has not got stays');
    expect(mine.single.updatedAt.toIso8601String(), endsWith('.000'), reason: 'taken from the catalogue, not the person\'s own edit');
    expect(mine.single.updatedAt.isAfter(DateTime(2026)), isTrue, reason: 'the newest, for team sync');
  });

  test('the catalogue\'s pcs (unit not known) never replaces a more exact unit; kinds only grow', () {
    final mine = [p('Acetamin 60ml'), p('Panadol')..kinds.add('grocery')];
    final plan = planSync(mine, {
      'Acetamin 60ml': cat('Acetamin 60ml', unit: 'pcs'),
      'Panadol': {...cat('Panadol'), 'kinds': 'pharmacy'},
    });
    expect(plan.fixes, isEmpty, reason: 'tab stays; pharmacy + grocery is not "fixed" to pharmacy');
    final more = planSync(
      [p('Strepsils')],
      {
        'Strepsils': {...cat('Strepsils'), 'kinds': 'pharmacy,grocery'},
      },
    );
    expect(more.fixes.single.changes, [(what: 'Kinds', mine: 'pharmacy', theirs: 'grocery, pharmacy')]);
    final tab = planSync([p('X')..unit = 'pcs'], {'X': cat('X', unit: 'tab')});
    expect(tab.fixes.single.changes, [(what: 'Unit', mine: 'pcs', theirs: 'tab')], reason: 'a known unit from the catalogue is still offered');
  });

  test('hand-made products not in the catalogue are offered to move; catalogue leftovers are not', () {
    final plan = planSync([p('My own soap', hand: true), p('Old catalogue copy')], {'My own soap': null, 'Old catalogue copy': null});
    expect(plan.handMade.map((x) => x.name), ['My own soap']);
  });

  test('selling prices and barcodes: Onboard\'s go up, the catalogue\'s come down where Onboard has none', () {
    final plan = planSync(
      [
        p('Panadol', selling: '40', codes: ['479']),
        p('Tel OD 20'),
        p('Amlo', codes: ['555']),
      ],
      {
        'Panadol': cat('Panadol', selling: '38', codes: ['479']),
        'Tel OD 20': cat('Tel OD 20', selling: '120', codes: ['888', '555']),
        'Amlo': cat('Amlo'),
      },
    );
    expect(plan.pricesUp.map((x) => (x.product.name, x.catalogue)), [('Panadol', '38')]);
    expect(plan.pricesDown.map((x) => (x.product.name, x.selling)), [('Tel OD 20', '120')]);
    expect(plan.codesUp.map((x) => (x.product.name, x.codes.join(','))), [('Amlo', '555')]);
    expect(plan.codesDown.map((x) => (x.product.name, x.codes.join(','))), [
      ('Tel OD 20', '888'),
    ], reason: 'a code another Onboard product has never comes down twice');
  });

  test('what goes up: moved products with their price and codes; never a cost', () {
    final soap = p('My own soap', selling: '120', codes: ['999'], hand: true)..cost = '80';
    final b = upBody(
      move: [soap],
      prices: [p('Panadol', selling: '40')],
      shopOf: (_) => 'Iman',
    );
    expect(b['add'], [
      {
        'name': 'My own soap',
        'unit': 'tab',
        'kinds': ['pharmacy'],
        'fields': <String, String>{},
      },
    ]);
    expect(b['prices'], [
      {'name': 'My own soap', 'selling': '120', 'shop': 'Iman'},
      {'name': 'Panadol', 'selling': '40', 'shop': 'Iman'},
    ]);
    expect(jsonEncode(b).contains('80'), isFalse, reason: 'a shop\'s buying price never leaves Onboard');
  });

  test('sign in keeps the app\'s session; match and up go with it', () async {
    final app = FakeShop();
    await app.start();
    addTearDown(() => app.server.close(force: true));
    app.routes = {
      'POST /api/signin': (r, body) {
        if ((jsonDecode(body) as Map)['pin'] != '123456') {
          r.response.statusCode = 403;
          return {'error': 'Wrong PIN'};
        }
        r.response.headers.add('Set-Cookie', 'ks_cat=tok; HttpOnly; SameSite=Strict; Path=/');
        return {'ok': true};
      },
      'POST /api/onboard/match': (r, _) {
        if (r.headers.value('cookie') != 'ks_cat=tok') {
          r.response.statusCode = 401;
          return {'error': 'Sign in'};
        }
        return {
          'matches': {
            'Panadol': {'id': 1, 'product': cat('Panadol 500mg')},
            'Soap': null,
          },
        };
      },
    };
    final c = CatalogueApp(app.url);
    await expectLater(c.signIn('000000'), throwsA(isA<CatalogueAppError>().having((e) => e.message, 'message', 'Wrong PIN')));
    await expectLater(c.match(['Panadol']), throwsA(isA<CatalogueAppError>()));
    await c.signIn('123456');
    final m = await c.match(['Panadol', 'Soap']);
    expect(m['Panadol']!['name'], 'Panadol 500mg');
    expect(m['Soap'], isNull);
  });
}
