import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/data/db.dart';
import 'package:karots_suite_onboard/data/drafts.dart';
import 'package:karots_suite_onboard/data/models.dart';
import 'package:karots_suite_onboard/main.dart';
import 'package:karots_suite_onboard/screens/product_form.dart';
import 'package:karots_suite_onboard/screens/shop_product_editor.dart';
import 'package:karots_suite_onboard/settings/secure.dart';
import 'package:karots_suite_onboard/state.dart';
import 'package:karots_suite_onboard/sync/push.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  testWidgets('Save & next saves, then starts a blank product with the last category and unit', (t) async {
    sqfliteFfiInit();
    final db = (await t.runAsync(() => Db.openWith(path: inMemoryDatabasePath, factory: databaseFactoryFfi)))!;
    final app = AppState(db, MemoryStore());
    final s = Shop(
      name: 'Iman',
      snapshot: {
        'categories': [
          {'id': 1, 'name': 'Pain', 'path': []},
        ],
        'units': [
          {'id': 1, 'abbreviation': 'pcs', 'isDefault': true},
          {'id': 2, 'abbreviation': 'tab'},
        ],
      },
    );
    shopNewDrafts[s.uid] = (draft: Draft(product: CatalogProduct(name: 'Panadol', category: 'Pain', unit: 'tab')), supplier: 'none');
    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await t.pump(const Duration(milliseconds: 400));
      }
    }

    await t.pumpWidget(buildApp(app: app, home: ShopProductEditor.newProduct(s)));
    await settle();
    await t.tap(find.text('Save & next'));
    await settle();

    final waiting = (await t.runAsync(() => db.pending(s.uid)))!;
    expect(waiting.single.data['product']['name'], 'Panadol'); // not connected: waits to push
    expect(find.text('New product'), findsOneWidget); // still here, ready for the next
    expect(find.widgetWithText(TextField, 'Panadol'), findsNothing);
    expect(find.widgetWithText(InputDecorator, 'Pain'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'tab'), findsOneWidget);
    expect(shopNewDrafts[s.uid], isNull);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
    await t.runAsync(() => db.close());
  });

  testWidgets('hidden fields are off the page but keep their values', (t) async {
    final form = GlobalKey<ProductFormState>();
    final p = CatalogProduct(name: 'Amoxil', nameLocal: 'ඇමොක්සිල්', wholesale: '90', packs: [Pack(name: 'Card', size: '10')], fields: {'Generic name': 'Amoxicillin'});
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProductForm(key: form, product: p, fieldLabels: const ['Generic name'], hidden: {'Local name', 'Wholesale price', 'Packs', 'More details'}),
          ),
        ),
      ),
    );
    expect(find.text('Local name'), findsNothing);
    expect(find.text('Wholesale price'), findsNothing);
    expect(find.text('Generic name'), findsNothing);
    expect(find.text('Warranty months'), findsOneWidget);
    final got = form.currentState!.read();
    expect(got.nameLocal, 'ඇමොක්සිල්');
    expect(got.wholesale, '90');
    expect(got.packs.single.size, '10');
    expect(got.fields['Generic name'], 'Amoxicillin');
  });
}
