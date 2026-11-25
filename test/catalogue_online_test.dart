import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/sync/catalogue_online.dart';

// Onboard takes only NEW products from the published catalogue (user, 2026-11-25).
void main() {
  test('the catalogue\'s duplicate rule, word for word as the catalogue repo (build/dedupe.py words)', () {
    final want = jsonDecode(File('test/catalogue_words.json').readAsStringSync()) as Map;
    expect(want.length, greaterThan(400));
    for (final e in want.entries) {
      expect(catalogueWords(e.key).toSet().toList()..sort(), (e.value as List).cast<String>(), reason: e.key);
    }
  });

  final items = [
    {
      'id': 1,
      'name': 'Panadol 500mg',
      'unit': 'tab',
      'kinds': 'pharmacy,grocery',
      'fields': {'Generic Name': 'Paracetamol', 'Company': ''},
    },
    {
      'id': 2,
      'name': 'Amlodipine 5mg (Cadila)',
      'unit': 'tab',
      'kinds': 'pharmacy',
      'fields': {'Generic Name': 'Amlodipine'},
    },
    {'id': 3, 'name': 'Samba Rice 5 kg', 'unit': '', 'kinds': 'grocery', 'fields': {}},
    {'id': 4, 'name': 'amlodipine 5 mg (cadila) tablets', 'unit': 'tab', 'kinds': 'pharmacy', 'fields': {}},
  ];

  test('only what Onboard hasn\'t got comes in; what it has is never touched', () {
    final got = newFromCatalogue(['Panadol 500mg Tabs', 'Samba rice 5kg'], items);
    expect(got.map((p) => p.name), [
      'Amlodipine 5mg (Cadila)',
      'amlodipine 5 mg (cadila) tablets',
    ], reason: 'same words as one Onboard has = already here; the catalogue\'s own twins (two makers) both come in');
    final a = got.first;
    expect(a.unit, 'tab');
    expect(a.kinds, {'pharmacy'});
    expect(a.fields, {'Generic Name': 'Amlodipine'});
    expect(a.cost, '');
    expect(a.updatedAt.toIso8601String(), endsWith('.000'), reason: 'the catalogue\'s date, never taken for the user\'s own edit');
  });

  test('a product with no unit gets pcs; nothing new when Onboard has it all', () {
    expect(newFromCatalogue([], items).firstWhere((p) => p.name.startsWith('Samba')).unit, 'pcs');
    expect(newFromCatalogue([for (final i in items) '${i['name']}'], items), isEmpty);
  });

  test('a download is used only when it matches the index', () {
    final body = gzip.encode(utf8.encode(jsonEncode({'version': 3, 'products': items})));
    final index = {
      'version': 3,
      'count': 4,
      'full': {'file': 'v3.json.gz', 'sha256': sha256.convert(body).toString()},
    };
    expect(readVersion(index, body).products.length, 4);
    expect(
      () => readVersion({
        ...index,
        'full': {'file': 'v3.json.gz', 'sha256': 'bad'},
      }, body),
      throwsA(isA<CatalogueError>()),
    );
    expect(() => readVersion({...index, 'count': 5}, body), throwsA(isA<CatalogueError>()));
  });
}
