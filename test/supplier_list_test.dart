import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/csv/supplier_list.dart';
import 'package:karots_suite_onboard/data/db.dart';
import 'package:karots_suite_onboard/data/models.dart';
import 'package:karots_suite_onboard/sync/review.dart';
import 'package:karots_suite_onboard/sync/supplier_import.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const csv =
    'Name,Barcode,Extra_Barcodes,Unit,Price,Pack_Name,Pack_Size,Pack_Price,Generic name,Strength\r\n'
    'Panadol 500mg Tablets,111,112;113,pcs,10.00,Card,12,115.00,Paracetamol,500 mg\r\n'
    'Amoxil 250mg Capsules,555,,pcs,25.00,,,,Amoxicillin,250 mg\r\n'
    ',,,,,,,,,\r\n';

void main() {
  sqfliteFfiInit();

  test('the template: the standard columns, two example details, one example row', () {
    final t = supplierListTemplate().split('\r\n');
    expect(t.first, 'name,barcode,extra_barcodes,unit,price,pack_name,pack_size,pack_price,Generic name,Strength');
    expect(t[1], startsWith('Panadol 500mg Tablets,'));
  });

  test('a list reads: any case of the headers, extra columns become details, blank rows skipped', () {
    final rows = readSupplierList(csv);
    expect(rows.length, 2);
    final a = rows.first;
    expect((a.name, a.barcode, a.selling, a.unit), ('Panadol 500mg Tablets', '111', '10.00', 'pcs'));
    expect(a.barcodes, ['112', '113']);
    expect(a.packs.single.selling, '115.00');
    expect(a.fields, {'Generic name': 'Paracetamol', 'Strength': '500 mg'});
    expect(() => readSupplierList('barcode,price\r\n1,2\r\n'), throwsA(isA<FormatException>()), reason: 'no name column');
  });

  test('importing: a known product gets its gaps filled and this supplier if it had none; new ones wait in Review', () async {
    final db = await Db.openWith(path: '${Directory.systemTemp.createTempSync('ob').path}/db', factory: databaseFactoryFfi);
    final hemas = CatalogSupplier(name: 'Hemas');
    await db.saveSupplier(hemas);
    await db.saveProduct(CatalogProduct(name: 'Panadol', barcode: '113', selling: '12', fields: {'Generic name': 'Paracetamol (shop)'}));
    final r = await importSupplierList(db, hemas, csv);
    expect((r.matched, r.toReview), (1, 1));
    final p = (await db.productByBarcode('113'))!;
    expect((p.name, p.selling, p.supplier), ('Panadol', '12', 'Hemas'), reason: 'the catalogue\'s own name and price stay');
    expect(p.allCodes.toSet(), {'113', '111', '112'});
    expect(p.fields, {'Generic name': 'Paracetamol (shop)', 'Strength': '500 mg'});
    expect(p.packs.single.name, 'Card');

    final rev = await db.reviews();
    expect(rev.single.shopUid, 'supplier:${hemas.uid}');
    await acceptReview(db, rev.single.uid);
    final amoxil = (await db.productByBarcode('555'))!;
    expect((amoxil.supplier, amoxil.selling, amoxil.fields['Generic name']), ('Hemas', '25.00', 'Amoxicillin'));
    expect(amoxil.cost, '', reason: 'cost isn\'t kept: it differs by supplier and changes');
    await db.close();
  });
}
