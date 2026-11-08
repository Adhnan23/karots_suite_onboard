import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/csv/export.dart';
import 'package:karots_suite_onboard/data/models.dart';
import 'package:karots_suite_onboard/sync/push.dart';

void main() {
  final shop = Shop(
    name: 'Iman',
    snapshot: {
      'fields': [
        {'key': 'generic_name', 'label': 'Generic name', 'isActive': true},
      ],
    },
  );

  test('the products sheet is the Suite\'s import format with the shop\'s custom fields', () {
    final d = Draft(
      product: CatalogProduct(
        name: 'Cable 2" grey, 10m',
        barcode: '1',
        barcodes: ['2', '3'],
        category: 'Hardware > Cables',
        unit: 'm',
        cost: '100',
        selling: '150',
        supplier: 'Lanka Wire',
        fields: {'Generic name': 'x'},
      ),
      mode: StockMode.several,
      batches: [
        StockBatch(qty: '5'),
        StockBatch(qty: '2.5'),
      ],
    );
    final lines = productsCsv([d], shop).split('\r\n');
    expect(
      lines.first,
      'name,name_local,barcode,extra_barcodes,category,unit,cost_price,selling_price,wholesale_price,tax_rate,reorder_level,opening_qty,supplier,track_serial,warranty_months,Generic name',
    );
    expect(lines[1], '"Cable 2"" grey, 10m",,1,2;3,Hardware > Cables,m,100,150,,,0,7.5,Lanka Wire,false,0,x');
  });

  test('the suppliers sheet', () {
    final out = suppliersCsv([CatalogSupplier(name: 'Hemas', contact: 'Ravi', phone: '077', creditDays: 30)]);
    expect(out.split('\r\n').take(2).toList(), ['name,contact_person,phone,address,credit_days,opening_balance', 'Hemas,Ravi,077,,30,']);
  });

  test('the count sheet is the Suite\'s stock-take format, from the shop\'s last pull', () {
    final rows = [
      {
        'name': 'Panadol, 500mg',
        'barcode': '111',
        'json': '{"name":"Panadol, 500mg","cost":"8.50","selling":"10.00","wholesale":"","openingQty":"40"}',
      },
    ];
    final lines = countSheetCsv(rows).split('\r\n');
    expect(lines.first, 'barcode,name,current_qty,counted_qty,cost,selling_price,wholesale_price,batch,expiry');
    expect(lines[1], '111,"Panadol, 500mg",40,,8.50,10.00,,,');
  });
}
