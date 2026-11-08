import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/data/db.dart';
import 'package:karots_suite_onboard/data/models.dart';
import 'package:karots_suite_onboard/sync/match.dart';
import 'package:karots_suite_onboard/sync/suite_csv.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('names compare without case or extra spaces', () {
    expect(normName('  Panadol  500MG '), 'panadol 500mg');
  });

  test('the Suite\'s product sheet reads back, Sinhala, commas and quotes too', () {
    const csv =
        'name,name_local,barcode,extra_barcodes,category,unit,cost_price,selling_price,wholesale_price,tax_rate,reorder_level,opening_qty,supplier,track_serial,warranty_months,Generic name,id\r\n'
        '"Panadol 500mg, Tabs",පැනඩෝල්,111,222;333,Medicine > Pain,pcs,8.50,10.00,0.00,0.00,0,40,Hemas,false,0,Paracetamol,7\r\n'
        '"Cable 2"" grey",,,,Hardware,m,1.00,2.00,0.00,0.00,0,0,,false,6,,8\r\n';
    final rows = readProductSheet(csv, const ['Generic name']);
    expect(rows.length, 2);
    final a = rows[0];
    expect(a.id, 7);
    expect(a.product.name, 'Panadol 500mg, Tabs');
    expect(a.product.nameLocal, 'පැනඩෝල්');
    expect(a.product.barcodes, ['222', '333']);
    expect(a.product.category, 'Medicine > Pain');
    expect(a.product.cost, '8.50');
    expect(a.product.supplier, 'Hemas');
    expect(a.product.fields, {'Generic name': 'Paracetamol'});
    expect(rows[1].product.name, 'Cable 2" grey');
    expect(rows[1].product.warrantyMonths, 6);
    expect(rows[1].product.fields, isEmpty);
  });

  test('a product is found by any of its codes, else by name', () async {
    sqfliteFfiInit();
    final db = await Db.openWith(path: inMemoryDatabasePath, factory: databaseFactoryFfi);
    final known = CatalogProduct(name: 'panadol 500mg', barcode: '111', barcodes: ['222']);
    await db.saveProduct(known);
    expect((await matchProduct(db, codes: ['999', '222'], name: 'x'))?.uid, known.uid);
    expect((await matchProduct(db, codes: [], name: 'Panadol  500MG '))?.uid, known.uid);
    expect(await matchProduct(db, codes: ['999'], name: 'Panadol 650'), isNull);
    await db.close();
  });
}
