import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/data/db.dart';
import 'package:karots_suite_onboard/data/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  test('a big catalogue (40,000 products, more than SQLite\'s 32,766 query values) loads whole', () async {
    final db = await Db.openWith(path: '${Directory.systemTemp.createTempSync('scale').path}/t.db', factory: databaseFactoryFfi);
    await db.raw.transaction((t) async {
      for (var i = 0; i < 40000; i++) {
        final uid = 'u$i';
        await t.insert('catalog_products', {'uid': uid, 'name': 'Product $i', 'barcode': '${100000 + i}', 'unit': 'pcs', 'updated_at': '2026-01-01'});
        await t.insert('catalog_barcodes', {'product_uid': uid, 'code': '${100000 + i}', 'pos': 0});
        await t.insert('catalog_fields', {'product_uid': uid, 'label': 'Generic Name', 'value': 'G$i'});
      }
    });
    final all = await db.products();
    expect(all.length, 40000);
    expect(all.firstWhere((p) => p.uid == 'u39999').fields['Generic Name'], 'G39999');
    await db.close();
  });

  test('a product\'s barcodes, packs and details are found by index, not by reading every row', () async {
    final db = await Db.openWith(path: '${Directory.systemTemp.createTempSync('idx').path}/t.db', factory: databaseFactoryFfi);
    for (final tb in ['catalog_barcodes', 'catalog_packs', 'catalog_fields', 'catalog_offers']) {
      final plan = (await db.raw.rawQuery('EXPLAIN QUERY PLAN SELECT * FROM $tb WHERE product_uid = ?', ['x'])).map((r) => '${r['detail']}').join(' ');
      expect(plan, contains('INDEX'), reason: '$tb: $plan');
    }
    await db.close();
  });

  test('saving many products at once keeps each one\'s barcodes, packs and details, and replaces old ones', () async {
    final db = await Db.openWith(path: '${Directory.systemTemp.createTempSync('many').path}/t.db', factory: databaseFactoryFfi);
    final a = CatalogProduct(
      name: 'A',
      barcode: '1',
      barcodes: ['2'],
      packs: [Pack(name: 'Card', size: '10')],
      fields: {'Generic Name': 'X'},
    );
    await db.saveProduct(a);
    final a2 = CatalogProduct.fromJson({
      ...a.toJson(),
      'barcodes': ['3'],
      'fields': {'Generic Name': 'Y'},
    });
    await db.saveProducts([a2, CatalogProduct(name: 'B', barcode: '9')]);
    final got = {for (final p in await db.products()) p.name: p};
    expect(got['A']!.allCodes, ['1', '3']);
    expect(got['A']!.fields, {'Generic Name': 'Y'});
    expect(got['A']!.packs.single.size, '10');
    expect(got['B']!.barcode, '9');
    expect(await db.productByBarcode('2'), isNull);
    await db.close();
  });
}
