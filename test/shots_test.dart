// Screens as pictures for a look, light and dark, phone and desktop:
//   SHOTS=/some/dir flutter test test/shots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/data/db.dart';
import 'package:karots_suite_onboard/data/models.dart';
import 'package:karots_suite_onboard/screens/alternatives_screen.dart';
import 'package:karots_suite_onboard/screens/catalog_screen.dart';
import 'package:karots_suite_onboard/screens/dupes_screen.dart';
import 'package:karots_suite_onboard/screens/review_screen.dart';
import 'package:karots_suite_onboard/screens/shop_actions.dart';
import 'package:karots_suite_onboard/screens/shop_product_editor.dart';
import 'package:karots_suite_onboard/screens/shop_screen.dart';
import 'package:karots_suite_onboard/screens/shops_screen.dart';
import 'package:karots_suite_onboard/settings/secure.dart';
import 'package:karots_suite_onboard/state.dart';
import 'package:karots_suite_onboard/sync/push.dart';
import 'package:karots_suite_onboard/theme/app_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> font(String family, List<String> files) async {
  final l = FontLoader(family);
  for (final f in files) {
    l.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await l.load();
}

void main() {
  final dir = Platform.environment['SHOTS'];
  testWidgets('shots', (t) async {
    await t.runAsync(() async {
      await font('Roboto', ['/usr/share/fonts/noto/NotoSans-Regular.ttf', '/usr/share/fonts/noto/NotoSans-Bold.ttf']);
      await font('MaterialIcons', ['/opt/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
    });
    registerShopActions();
    sqfliteFfiInit();
    final db = (await t.runAsync(() => Db.openWith(path: inMemoryDatabasePath, factory: databaseFactoryFfi)))!;
    final shop = Shop(name: 'Iman Pharmacy', kind: 'pharmacy', address: 'http://100.101.5.2:3000', installId: 'FC1A79F7', lastPull: DateTime(2026, 11, 8, 9, 30), snapshot: {
      'plugins': ['aicatalog', 'alternatives', 'productplus', 'pharmacy', 'combos'],
      'stockTake': true,
      'categories': [{'id': 1, 'name': 'Medicine', 'path': []}, {'id': 2, 'name': 'Pain', 'path': [1]}],
      'units': [{'id': 1, 'abbreviation': 'pcs'}],
      'suppliers': [{'id': 3, 'name': 'Hemas Pharma'}],
      'fields': [{'id': 1, 'key': 'generic_name', 'label': 'Generic name', 'isActive': true}, {'id': 2, 'key': 'strength', 'label': 'Strength', 'isActive': true}],
      'alternatives': [{'id': 1, 'name': 'Paracetamol 500', 'tiers': [{'id': 1, 'name': 'Tablets', 'members': [{'productId': 1, 'name': 'Panadol 500mg'}, {'productId': 2, 'name': 'Calpol 500mg'}]}]}],
    });
    await t.runAsync(() async {
      await db.saveShop(shop);
      await db.saveShop(Shop(name: 'Ranjith Hardware', kind: 'hardware', address: 'http://192.168.1.20:3000'));
      for (final p in [
        CatalogProduct(name: 'Panadol 500mg Tablets', barcode: '4792210100015', category: 'Medicine > Pain', selling: '12.00', kinds: {'pharmacy'},
            packs: [Pack(name: 'Card', size: '12', selling: '140')], fields: {'Generic name': 'Paracetamol'}),
        CatalogProduct(name: 'panadol 500 mg tabs', category: 'Medicine > Pain', selling: '12.00', kinds: {'pharmacy'}),
        CatalogProduct(name: 'PVC Pipe 1" 6m', category: 'Plumbing', selling: '1850.00', kinds: {'hardware'}),
        CatalogProduct(name: 'Amoxil 250mg Capsules', category: 'Medicine > Antibiotics', selling: '25.00', kinds: {'pharmacy'}, fields: {'Generic name': 'Amoxicillin'}),
      ]) {
        await db.saveProduct(p);
      }
      await db.addReview(ReviewItem(shopUid: shop.uid, kind: 'product', data: CatalogProduct(name: 'Piriton 4mg', barcode: '501', category: 'Medicine > Allergy', selling: '6.00', fields: {'Generic name': 'Chlorphenamine'}).toJson()), key: '501');
      await db.addReview(ReviewItem(shopUid: shop.uid, kind: 'product', data: CatalogProduct(name: 'Siddhalepa Balm 25g', category: 'Ayurveda', selling: '320.00', packs: [Pack(name: 'Box', size: '6')]).toJson()), key: 'sb');
      await db.addReview(ReviewItem(shopUid: shop.uid, kind: 'supplier', data: CatalogSupplier(name: 'State Pharmaceuticals', phone: '0112 345 678').toRow()), key: 'spc');
    });
    final app = AppState(db, MemoryStore());
    final screens = <String, Widget>{
      'shops': const ShopsScreen(),
      'shop': ShopScreen(shop: shop),
      'review': const ReviewScreen(),
      'catalogue': const CatalogScreen(),
      'editor': ShopProductEditor(shop: shop, draft: Draft(product: CatalogProduct(name: 'Panadol 500mg Tablets', category: 'Medicine > Pain', cost: '9.50', selling: '12.00', fields: {'Generic name': 'Paracetamol'}), mode: StockMode.several, batches: [StockBatch(qty: '120', expiry: '2027-12-31'), StockBatch(qty: '48', expiry: '2028-06-30', selling: '13.00')])),
      'duplicates': const DupesScreen(),
      'alternatives': AlternativesScreen(shop: shop),
    };
    for (final size in [const Size(390, 844), const Size(1280, 800)]) {
      for (final b in Brightness.values) {
        for (final e in screens.entries) {
          await t.binding.setSurfaceSize(size);
          final key = GlobalKey();
          await t.pumpWidget(RepaintBoundary(
            key: key,
            child: AppScope(state: app, child: MaterialApp(debugShowCheckedModeBanner: false, theme: ksTheme(b, fonts: false), home: e.value)),
          ));
          await t.runAsync(() => Future.delayed(const Duration(milliseconds: 250)));
          await t.pump();
          await t.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
          await t.pump();
          if (dir == null) continue;
          final img = await t.runAsync(() async {
            final i = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 1.5);
            return (await i.toByteData(format: ui.ImageByteFormat.png))!;
          });
          final w = size.width < 500 ? 'phone' : 'desktop';
          File('$dir/${e.key}-$w-${b.name}.png').writeAsBytesSync(img!.buffer.asUint8List());
        }
      }
    }
    await t.runAsync(() => db.close());
  }, skip: dir == null);
}
