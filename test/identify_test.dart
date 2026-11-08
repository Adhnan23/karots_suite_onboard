import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/ai/identify.dart';
import 'package:karots_suite_onboard/data/models.dart';

void main() {
  final shop = Shop(
    name: 'Iman',
    snapshot: {
      'categories': [
        {'id': 1, 'name': 'Medicine', 'path': []},
        {
          'id': 2,
          'name': 'Pain',
          'path': [1],
        },
        {'id': 3, 'name': 'Cleaning', 'path': []},
      ],
      'fields': [
        {
          'key': 'generic_name',
          'label': 'Generic name',
          'type': 'text',
          'isActive': true,
          'options': [],
          'scope': [
            {'id': 1, 'name': 'Medicine'},
            {'id': 2, 'name': 'Pain'},
          ],
        },
        {
          'key': 'form',
          'label': 'Form',
          'type': 'select',
          'isActive': true,
          'options': ['Tablet', 'Capsule'],
          'scope': [],
        },
        {'key': 'rack', 'label': 'Rack', 'type': 'text', 'isActive': true, 'options': [], 'scope': []},
      ],
      'ai': {
        'namingStyle': 'Brand Strength Form',
        'customPrompt': 'We are a pharmacy',
        'identifyFields': ['generic_name', 'form'],
      },
    },
  );

  test('the offline prompt follows the shop\'s AI settings and ticked fields', () {
    final p = identifyPrompt(shop, 'panadl 500', barcode: '4792');
    for (final want in [
      'Identify this item: panadl 500',
      'Barcode: 4792',
      'Brand Strength Form',
      'We are a pharmacy',
      'generic_name (Generic name, text), only for categories: Medicine; Medicine > Pain',
      'form (Form, dropdown, pick one only: Tablet, Capsule)',
      '- Medicine > Pain',
      '"values"',
    ]) {
      expect(p, contains(want));
    }
    expect(p, isNot(contains('rack')));
  });

  test('a fenced reply reads; values land on field labels, only where they fit', () {
    final r = parseIdentify(
      shop,
      'Sure!\n```json\n{"confident":true,"best":{"name":"Panadol 500mg Tablets","category":"Medicine > Pain","specs":"500 mg","explanation":"For pain","values":{"generic_name":"Paracetamol","form":"tablet","rack":"A1"}}}\n```',
    );
    expect(r.confident, isTrue);
    final b = r.candidates.single;
    expect(b.name, 'Panadol 500mg Tablets');
    expect(b.fields, {'Generic name': 'Paracetamol', 'Form': 'Tablet'});
    final cleaning = parseIdentify(
      shop,
      '{"confident":true,"best":{"name":"Harpic","category":"Cleaning","values":{"generic_name":"x","form":"Liquid"}}}',
    );
    expect(cleaning.candidates.single.fields, isEmpty, reason: 'a medicine-only field on a cleaner, and a dropdown answer off the list');
  });

  test('the shop\'s own answer (connected) reads the same way', () {
    final r = fromShopResult({
      'confident': false,
      'options': [
        {
          'name': 'A',
          'category': 'Medicine',
          'specs': '',
          'explanation': '',
          'fields': [
            {'key': 'generic_name', 'label': 'Generic name', 'value': 'X'},
          ],
        },
        {'name': 'B', 'category': '', 'specs': '', 'explanation': ''},
      ],
    });
    expect(r.candidates.map((c) => c.name), ['A', 'B']);
    expect(r.candidates.first.fields, {'Generic name': 'X'});
  });
}
