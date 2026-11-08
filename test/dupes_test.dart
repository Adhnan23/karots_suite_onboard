import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/data/db.dart';
import 'package:karots_suite_onboard/data/models.dart';
import 'package:karots_suite_onboard/dupes/find.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('same item written two ways is paired; another size is not', () {
    final a = CatalogProduct(name: 'Panadol 500mg Tabs');
    final b = CatalogProduct(name: 'panadol 500 mg tablets');
    final c = CatalogProduct(name: 'Panadol 650mg Tabs');
    final d = CatalogProduct(name: 'Something', barcode: '1');
    final e = CatalogProduct(name: 'Other thing', barcodes: ['1']);
    final pairs = findDupes([a, b, c, d, e]);
    final names = {
      for (final p in pairs) {p.a.name, p.b.name},
    };
    expect(
      names,
      containsAll([
        {'Panadol 500mg Tabs', 'panadol 500 mg tablets'},
        {'Something', 'Other thing'},
      ]),
    );
    expect(names.any((n) => n.contains('Panadol 650mg Tabs')), isFalse);
    expect(pairs.firstWhere((p) => p.a.name == 'Something' || p.b.name == 'Something').why, 'same barcode');
  });

  test('merging keeps every barcode, fills gaps, and joins shops and kinds', () async {
    sqfliteFfiInit();
    final db = await Db.openWith(path: inMemoryDatabasePath, factory: databaseFactoryFfi);
    final keep = CatalogProduct(name: 'Panadol 500mg', barcode: '111', kinds: {'pharmacy'}, sources: {'s1'}, fields: {'Generic name': 'Paracetamol'});
    final drop = CatalogProduct(
      name: 'Panadol 500 mg',
      barcode: '222',
      category: 'Medicine',
      selling: '10',
      kinds: {'grocery'},
      sources: {'s2'},
      packs: [Pack(name: 'Card', size: '12')],
      fields: {'Generic name': 'x', 'Form': 'Tablet'},
    );
    await db.saveProduct(keep);
    await db.saveProduct(drop);
    await mergeCatalog(db, keep.uid, drop.uid);
    final all = await db.products();
    expect(all.length, 1);
    final m = all.single;
    expect(m.allCodes, ['111', '222']);
    expect(m.category, 'Medicine');
    expect(m.selling, '10');
    expect(m.packs.single.name, 'Card');
    expect(m.fields, {'Generic name': 'Paracetamol', 'Form': 'Tablet'});
    expect(m.kinds, {'pharmacy', 'grocery'});
    expect(m.sources, {'s1', 's2'});
    await db.close();
  });
}
