import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/data/models.dart';
import 'package:karots_suite_onboard/sync/push.dart';
import 'package:karots_suite_onboard/sync/quick.dart';

void main() {
  final panadol = CatalogProduct(
    name: 'Panadol 500mg',
    barcode: '111',
    barcodes: ['112'],
    category: 'X',
    selling: '12',
    offers: [
      Offer(supplierUid: 'a', supplierName: 'Hemas', cost: '9.00', price: '12.50'),
      Offer(supplierUid: 'b', supplierName: 'SPC', cost: '8.50', price: '12.00'),
    ],
  );
  final amoxil = CatalogProduct(name: 'Amoxil 250', barcode: '555');
  final cat = [panadol, amoxil, CatalogProduct(name: 'Panadol Extra')];

  test('a scan finds by any barcode; words find by name; the shop\'s own copy is spotted', () {
    expect(quickFind(cat, [], '112').catalogue.single.name, 'Panadol 500mg');
    expect(quickFind(cat, [], 'panadol').catalogue.map((p) => p.name), ['Panadol 500mg', 'Panadol Extra']);
    final inShop = quickFind(cat, [
      {'remote_id': 7, 'name': 'PANADOL 500MG', 'barcode': '999'},
    ], '111');
    expect(inShop.inShop?['remote_id'], 7, reason: 'same name in the shop: add stock there, no twin');
    expect(
      quickFind(cat, [
        {'remote_id': 8, 'name': 'x', 'barcode': '555'},
      ], '555').inShop?['remote_id'],
      8,
    );
    expect(quickFind(cat, [], '000').catalogue, isEmpty);
  });

  test('the sheet starts from the cheapest supplier\'s cost and the catalogue\'s price', () {
    final s = quickStart(panadol);
    expect((s.cost, s.price), ('8.50', '12'));
    expect((quickStart(amoxil).cost, quickStart(amoxil).price), ('', ''));
  });

  test('what is sent: the catalogue product, no category, the typed prices and one batch', () {
    final d = quickDraft(panadol, cost: '8.75', price: '13', qty: '24', expiry: '2027-12-31');
    expect((d.product.name, d.product.category, d.product.cost, d.product.selling), ('Panadol 500mg', '', '8.75', '13'));
    expect(d.mode, StockMode.one);
    expect((d.stock.single.qty, d.stock.single.expiry), ('24', '2027-12-31'));
    expect(quickDraft(panadol, cost: '1', price: '2', qty: '', expiry: '').stock, isEmpty);
  });
}
