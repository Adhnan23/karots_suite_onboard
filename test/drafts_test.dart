import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/data/db.dart';
import 'package:karots_suite_onboard/data/drafts.dart';
import 'package:karots_suite_onboard/data/models.dart';
import 'package:karots_suite_onboard/sync/push.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('drafts survive the app being closed, and a dropped one stays dropped', () async {
    final dir = await Directory.systemTemp.createTemp('drafts');
    final path = '${dir.path}/onboard.db';
    var db = await Db.openWith(path: path, factory: databaseFactoryFfi);
    await loadDrafts(db);
    catalogNewDraft = CatalogProduct(name: 'Nataraj Geometry Box', selling: '450')..barcodes = ['8901234567890'];
    shopNewDrafts['shop-1'] = (
      draft: Draft(
        product: CatalogProduct(name: 'Panadol', cost: '9.50'),
        mode: StockMode.one,
      ),
      supplier: 'shop:7',
    );
    shopNewDrafts['shop-2'] = (draft: Draft(product: CatalogProduct(name: 'Gone')), supplier: 'none');
    await keepDrafts();
    shopNewDrafts.remove('shop-2');
    await keepDrafts();
    await db.close();

    catalogNewDraft = null; // the app closed: memory is gone
    shopNewDrafts.clear();
    db = await Db.openWith(path: path, factory: databaseFactoryFfi);
    await loadDrafts(db);
    expect((catalogNewDraft?.name, catalogNewDraft?.selling), ('Nataraj Geometry Box', '450'));
    expect(catalogNewDraft?.barcodes, ['8901234567890']);
    final kept = shopNewDrafts['shop-1']!;
    expect((kept.draft.product.name, kept.draft.product.cost, kept.draft.mode, kept.supplier), ('Panadol', '9.50', StockMode.one, 'shop:7'));
    expect(shopNewDrafts.containsKey('shop-2'), isFalse);

    await db.raw.insert('drafts', {'key': 'shop:bad', 'json': '{broken'});
    await loadDrafts(db);
    expect(shopNewDrafts.keys, ['shop-1'], reason: 'an unreadable draft is dropped, never a crash');
    await db.close();
    await dir.delete(recursive: true);
  });
}
