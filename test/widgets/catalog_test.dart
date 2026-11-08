import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/data/models.dart';
import 'package:karots_suite_onboard/screens/catalog_screen.dart';
import 'package:karots_suite_onboard/screens/product_form.dart';
import 'package:karots_suite_onboard/theme/app_theme.dart';

void main() {
  final all = [
    CatalogProduct(name: 'Panadol 500mg', barcode: '111', kinds: {'pharmacy'}),
    CatalogProduct(name: 'PVC Pipe 1"', barcodes: ['777'], kinds: {'hardware'}),
    CatalogProduct(name: 'Panadol Extra', kinds: {'pharmacy', 'grocery'}),
  ];

  test('search by name or any barcode, filter by kind of shop', () {
    expect(filterCatalog(all, 'panadol', null).length, 2);
    expect(filterCatalog(all, '777', null).single.name, 'PVC Pipe 1"');
    expect(filterCatalog(all, '', 'grocery').single.name, 'Panadol Extra');
    expect(filterCatalog(all, 'pipe', 'pharmacy'), isEmpty);
  });

  testWidgets('the product form edits name, prices, a pack and a custom field', (t) async {
    final p = CatalogProduct(name: 'Panadol', selling: '10.00', fields: {'Generic name': ''});
    final key = GlobalKey<ProductFormState>();
    await t.pumpWidget(
      MaterialApp(
        theme: ksTheme(Brightness.light, fonts: false),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProductForm(key: key, product: p, fieldLabels: const ['Generic name']),
          ),
        ),
      ),
    );
    await t.enterText(find.widgetWithText(TextField, 'Name'), 'Panadol 500mg Tablets');
    await t.enterText(find.widgetWithText(TextField, 'Selling price'), '12.50');
    await t.enterText(find.widgetWithText(TextField, 'Generic name'), 'Paracetamol');
    await t.ensureVisible(find.text('Add pack'));
    await t.tap(find.text('Add pack'));
    await t.pump();
    await t.enterText(find.widgetWithText(TextField, 'Pack name'), 'Card');
    await t.enterText(find.widgetWithText(TextField, 'Units in it'), '12');
    final got = key.currentState!.read();
    expect(got.name, 'Panadol 500mg Tablets');
    expect(got.selling, '12.50');
    expect(got.fields['Generic name'], 'Paracetamol');
    expect(got.packs.single.name, 'Card');
    expect(got.packs.single.size, '12');
    expect(got.uid, p.uid);
  });
}
