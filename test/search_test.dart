import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/data/models.dart';
import 'package:karots_suite_onboard/sync/search.dart';

void main() {
  final augmentin = CatalogProduct(
    name: 'Augmentin 625mg',
    barcode: '5000123',
    category: 'Antibiotics',
    supplier: 'British Agencies',
    fields: {'Generic Name': 'Co-Amoxiclav', 'Company': 'GlaxoSmithKline'},
  );
  final evion = CatalogProduct(name: 'Evion 400mg', fields: {'Generic Name': 'Vitamin E'});
  final ventolin = CatalogProduct(name: 'Ventolin Syrup 100ml', fields: {'Generic Name': 'Salbutamol'});
  final all = [evion, augmentin, ventolin];
  List<String> s(String q) => [for (final p in searchProducts(all, q)) p.name];

  test('finds by any field: generic, company, category, supplier, barcode', () {
    expect(s('amoxiclav'), ['Augmentin 625mg']);
    expect(s('glaxo'), ['Augmentin 625mg']);
    expect(s('antibiotics'), ['Augmentin 625mg']);
    expect(s('british'), ['Augmentin 625mg']);
    expect(s('5000123'), ['Augmentin 625mg']);
  });

  test('every word must match somewhere, in any order', () {
    expect(s('625 augmentin'), ['Augmentin 625mg']);
    expect(s('augmentin 400'), isEmpty);
    expect(s('salbutamol syrup'), ['Ventolin Syrup 100ml']);
  });

  test('tolerates typos and spacing', () {
    expect(s('augmentn'), ['Augmentin 625mg']);
    expect(s('salbutmol'), ['Ventolin Syrup 100ml']);
    expect(s('ventolin 100 ml'), ['Ventolin Syrup 100ml']);
    expect(s('evion400'), ['Evion 400mg']);
    expect(s('vitamn e'), ['Evion 400mg']);
    expect(s('viamin e'), ['Evion 400mg']);
    expect(s('xyzzy'), isEmpty);
  });

  test('short words never fuzzy-match, numbers are exact', () {
    expect(s('625'), ['Augmentin 625mg']);
    expect(s('626'), isEmpty);
  });

  test('exact before typo, name before other fields', () {
    final generic = CatalogProduct(name: 'Panadol', fields: {'Generic Name': 'Paracetamol'});
    final named = CatalogProduct(name: 'Paracetamol 500mg (SPC)');
    final typo = CatalogProduct(name: 'Paracetamal Syrup');
    expect([for (final p in searchProducts([typo, generic, named], 'paracetamol')) p.name],
        ['Paracetamol 500mg (SPC)', 'Panadol', 'Paracetamal Syrup']);
  });

  test('an empty search keeps everything in order', () {
    expect(s('  '), ['Evion 400mg', 'Augmentin 625mg', 'Ventolin Syrup 100ml']);
  });
}
