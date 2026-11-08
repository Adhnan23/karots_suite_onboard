import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/csv/supplier_list.dart';
import 'package:karots_suite_onboard/data/db.dart';
import 'package:karots_suite_onboard/data/models.dart';
import 'package:karots_suite_onboard/sync/review.dart';
import 'package:karots_suite_onboard/sync/supplier_import.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const csv =
    'Name,Barcode,Extra_Barcodes,Supplier_Code,Unit,Cost,Price,Pack_Name,Pack_Size,Pack_Price,Generic name,Strength\r\n'
    'Panadol 500mg Tablets,111,112;113,HM-001,pcs,8.50,10.00,Card,12,115.00,Paracetamol,500 mg\r\n'
    'Amoxil 250mg Capsules,555,,HM-002,pcs,20.00,25.00,,,,Amoxicillin,250 mg\r\n'
    ',,,,,,,,,,,\r\n';

void main() {
  sqfliteFfiInit();

  test('the template is the standard header with an example row', () {
    final t = supplierListTemplate().split('\r\n');
    expect(t.first, 'name,barcode,extra_barcodes,supplier_code,unit,cost,price,pack_name,pack_size,pack_price,Generic name,Strength');
    expect(t[1], startsWith('Panadol 500mg Tablets,'));
  });

  test('a list reads: any case of the headers, extra columns become details, blank rows skipped', () {
    final rows = readSupplierList(csv);
    expect(rows.length, 2);
    final a = rows.first;
    expect((a.product.name, a.product.barcode), ('Panadol 500mg Tablets', '111'));
    expect(a.product.barcodes, ['112', '113']);
    expect((a.code, a.cost, a.price), ('HM-001', '8.50', '10.00'));
    expect(a.product.packs.single.name, 'Card');
    expect(a.product.packs.single.selling, '115.00');
    expect(a.product.fields, {'Generic name': 'Paracetamol', 'Strength': '500 mg'});
    expect(rows[1].product.packs, isEmpty);
    expect(() => readSupplierList('barcode,price\r\n1,2\r\n'), throwsA(isA<FormatException>()), reason: 'no name column');
  });

  test('importing: a known product gets the supplier\'s offer and its gaps filled; new ones go to Review', () async {
    final db = await Db.openWith(path: '${Directory.systemTemp.createTempSync('ob').path}/db', factory: databaseFactoryFfi);
    final hemas = CatalogSupplier(name: 'Hemas');
    await db.saveSupplier(hemas);
    await db.saveProduct(CatalogProduct(name: 'Panadol', barcode: '113', fields: {'Generic name': 'Paracetamol (shop)'}));
    final r = await importSupplierList(db, hemas, csv);
    expect((r.matched, r.toReview), (1, 1));
    final p = (await db.productByBarcode('113'))!;
    expect(p.name, 'Panadol', reason: 'the catalogue\'s name stays');
    expect(p.allCodes.toSet(), {'113', '111', '112'});
    expect(p.fields, {'Generic name': 'Paracetamol (shop)', 'Strength': '500 mg'}, reason: 'gaps filled, nothing overwritten');
    expect(p.packs.single.name, 'Card');
    expect(p.offers.single.supplierName, 'Hemas');
    expect((p.offers.single.code, p.offers.single.cost, p.offers.single.price), ('HM-001', '8.50', '10.00'));

    // the same list again: the offer is updated, not doubled; nothing new for Review
    final again = await importSupplierList(db, hemas, csv.replaceFirst('8.50', '8.75'));
    expect((again.matched, again.toReview), (1, 0));
    expect((await db.productByBarcode('113'))!.offers.single.cost, '8.75');

    final rev = await db.reviews();
    expect(rev.single.shopUid, 'supplier:${hemas.uid}');
    await acceptReview(db, rev.single.uid);
    final amoxil = (await db.productByBarcode('555'))!;
    expect(amoxil.offers.single.code, 'HM-002');
    expect(amoxil.fields['Generic name'], 'Amoxicillin');
    expect(amoxil.cost, '20.00', reason: 'a new product takes the supplier\'s prices as its suggestion');
    await db.close();
  });
}
