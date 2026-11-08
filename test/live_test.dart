// Against a running dev Suite with every plugin (make plugins P=all; make dev):
//   LIVE_SUITE=http://localhost:3000 flutter test test/live_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/ai/identify.dart';
import 'package:karots_suite_onboard/data/db.dart';
import 'package:karots_suite_onboard/data/models.dart';
import 'package:karots_suite_onboard/suite/client.dart';
import 'package:karots_suite_onboard/sync/lots.dart';
import 'package:karots_suite_onboard/sync/pull.dart';
import 'package:karots_suite_onboard/sync/push.dart';
import 'package:karots_suite_onboard/sync/review.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final url = Platform.environment['LIVE_SUITE'];
  test(
    'the whole round trip on a real Suite',
    () async {
      sqfliteFfiInit();
      final db = await Db.openWith(path: inMemoryDatabasePath, factory: databaseFactoryFfi);
      final c = SuiteClient(url!);
      final info = await c.loginInfo();
      await c.signIn('no-secret-in-dev', info.installId);
      final me = await c.me();
      expect(me.plugins, containsAll(['productplus', 'alternatives', 'aicatalog']));
      if (!me.stockTakeEnabled) await c.enableStockTake();
      expect((await c.me()).stockTakeEnabled, isTrue);
      final tag = DateTime.now().millisecondsSinceEpoch % 100000;

      // A custom field ticked for Identify, as at Iman.
      final f = await c.post('/x/productplus/fields', {'label': 'Generic $tag', 'type': 'text', 'scope': []}) as Map;
      final ai = await c.aiSettings();
      await c.put('/x/aicatalog/settings', {
        ...ai,
        'manualMode': true,
        'identifyFields': ['${f['key']}'],
      });

      final shop = Shop(name: 'Dev', kind: 'grocery', address: url, installId: info.installId);
      await db.saveShop(shop);
      final r1 = await pull(db, c, shop);
      expect(r1.toReview, greaterThan(0));
      for (final x in await db.reviews()) {
        await acceptReview(db, x.uid);
      }
      expect((await db.products()).length, greaterThanOrEqualTo(r1.toReview));

      // A new product: pack, extra barcode, custom field, new supplier, two batches of old stock.
      final d = Draft(
        product: CatalogProduct(
          name: 'Onboard Test $tag',
          barcode: 'OB$tag',
          barcodes: ['OBX$tag'],
          category: 'Onboard > Tests',
          unit: 'pcs',
          cost: '40',
          selling: '50',
          packs: [Pack(name: 'Box', size: '10', selling: '480', barcode: 'OBB$tag')],
          fields: {'Generic $tag': 'Testamol'},
        ),
        newSupplier: CatalogSupplier(name: 'Onboard Supplier $tag'),
        mode: StockMode.several,
        batches: [
          StockBatch(qty: '6', expiry: '2027-12-31'),
          StockBatch(qty: '4', expiry: '2028-06-30', cost: '42', selling: '55'),
        ],
      );
      final r = await pushCreate(db, c, shop, d);
      expect(r.failed, isEmpty);
      final p = await c.product(r.productId);
      expect(p['name'], 'Onboard Test $tag');
      expect('${p['stockQty']}', anyOf('10', '10.000', '10.00'));
      final packs = (await c.allPacks())[r.productId]!;
      expect(packs.single['name'], 'Box');
      final lots = await c.get('/till/products/${r.productId}/lots') as List;
      expect(lots.length, 2, reason: 'one lot per batch');
      final form = await c.get('/x/productplus/form', {'productId': '${r.productId}', 'categoryId': '${p['categoryId']}', 'where': 'form'}) as List;
      expect(form.firstWhere((x) => x['key'] == f['key'])['value'], 'Testamol');

      // Its batches: read, then fix one's count, expiry and price.
      var st = await productStock(c, r.productId);
      expect(st.lots.length, 2);
      final second = st.lots.firstWhere((l) => l.expiry == '2028-06-30');
      await editLot(c, r.productId, st, second, count: '7', expiry: '2028-09-30', price: '57');
      st = await productStock(c, r.productId);
      final fixed = st.lots.firstWhere((l) => l.id == second.id);
      expect((fixed.qty, fixed.expiry, fixed.price), ('7', '2028-09-30', '57.00'));
      expect(st.total, '13');

      // Change it.
      await pushUpdate(
        db,
        c,
        shop,
        Draft(product: CatalogProduct.fromJson({...d.product.toJson(), 'name': 'Onboard Test $tag Changed', 'selling': '52'}), remoteId: r.productId),
      );
      expect((await c.product(r.productId))['name'], 'Onboard Test $tag Changed');

      // Identify through the shop (paste mode: a prompt with the ticked field), then the reply.
      final ask = {'query': 'panadl 500', 'barcode': '', 'hint': '', 'short': false};
      final pr = await c.identify(ask);
      expect('${pr['prompt']}', contains('Generic $tag'));
      final ans = await c.identify({
        ...ask,
        'reply':
            '{"confident":true,"best":{"name":"Panadol 500mg","category":"Onboard > Tests","specs":"","explanation":"x","values":{"${f['key']}":"Paracetamol"}}}',
      });
      expect(fromShopResult(ans['result'] as Map).candidates.single.fields, {'Generic $tag': 'Paracetamol'});

      // An Alternatives group and a merge preview with a second product.
      final d2 = Draft(
        product: CatalogProduct(name: 'Onboard Twin $tag', category: 'Onboard > Tests', cost: '1', selling: '2'),
      );
      final r2 = await pushCreate(db, c, shop, d2);
      final gid = await c.createAlternative('Onboard Group $tag', 'All', [r.productId, r2.productId]);
      final g = await c.get('/x/alternatives/$gid') as Map;
      expect(((g['tiers'] as List).single['members'] as List).length, 2);
      final pv = await c.mergePreview(r2.productId, r.productId);
      expect(pv['intoName'], 'Onboard Test $tag Changed');
      await c.merge(r2.productId, r.productId);

      final r3 = await pull(db, c, shop);
      expect(r3.toReview, 0, reason: 'everything made here is already in the catalogue');
      await db.close();
    },
    skip: url == null ? 'set LIVE_SUITE to a running dev Suite' : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
