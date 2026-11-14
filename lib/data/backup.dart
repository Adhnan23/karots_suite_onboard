import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../sync/match.dart';
import 'db.dart';
import 'models.dart';

/// The app's own data as one file: the catalogue's products and suppliers, and
/// the shop profiles with their last pulls. Never the support secrets.
/// Everything, or (since: a [Db.stamp] this device gave earlier as 'changes') only what
/// changed here after it: the team sync's way of not sending 50,000 products every time.
/// Suppliers always go whole (few). 'changes' marks this export for the next one.
Future<String> exportBackup(Db db, {String? since}) async {
  final changes = Db.stamp(); // before reading: a change made while exporting goes next time too
  final changed = since == null ? '1=1' : 'changed_at > ?', args = [?since];
  final shops = <Map<String, Object?>>[];
  for (final s in await db.shops(where: changed, args: args)) {
    shops.add({...s.toRow(), 'products': await db.shopProducts(s.uid)});
  }
  return (since == null ? const JsonEncoder.withIndent(' ') : const JsonEncoder()).convert({
    'kind': 'karots_onboard.backup',
    'schema': 1,
    'at': DateTime.now().toIso8601String(),
    'changes': changes,
    'products': [for (final p in await db.products(where: changed, args: args)) p.toJson()],
    'suppliers': [for (final x in await db.suppliers()) x.toRow()],
    'shops': shops,
    'deleted': await db.deletions(since: since),
  });
}

/// What a long job is doing, for the screen: words with numbers, and how far
/// (0–1) when it can tell (null: a spinning bar).
typedef SyncStep = ({String text, double? part});

/// Every 500th item: says how far, and lets the screen draw (a 50,000-item loop
/// would otherwise freeze the app until it ends).
Future<void> tell(ValueNotifier<SyncStep?>? step, int i, int n, String what, [String unit = '']) async {
  if (i % 500 != 0) return;
  step?.value = (text: '$what $i of $n${unit.isEmpty ? '' : ' $unit'}', part: n == 0 ? null : i / n);
  await Future<void>.delayed(Duration.zero);
}

class ImportResult {
  ImportResult(this.products, this.suppliers, this.shops, {this.received = 0, this.changes});
  final int products, suppliers, shops;

  /// Products in the file (changed or not), and the file's 'changes' mark.
  final int received;
  final String? changes;
}

/// Merges a backup in: what's missing is added; the same product (by id, barcode
/// or name) takes the newer edit; a supplier already here (by name) stays; a shop
/// takes the newer pull. Counts what changed.
Future<ImportResult> importBackup(Db db, String text, {ValueNotifier<SyncStep?>? step}) async {
  final m = jsonDecode(text);
  if (m is! Map || m['kind'] != 'karots_onboard.backup') throw const FormatException('That isn\'t a Karots Onboard backup');
  var products = 0, suppliers = 0, shops = 0;

  // Deletions first: what the other device deleted goes here too, unless it was
  // changed here after that (a product's own time says so).
  // Each kind's deleted list is read once and kept current here: re-reading it per entry made a file with
  // 114 deletions take minutes when the list held 34,000 (a wiped catalogue).
  final deleted = <String, Map<String, DateTime>>{};
  final marks = <(String, String, DateTime)>[];
  final dels = m['deleted'] as List? ?? [];
  for (final (i, r) in dels.indexed) {
    await tell(step, i, dels.length, 'Checking deletions');
    final kind = '${r['kind']}', uid = '${r['uid']}', at = DateTime.parse('${r['at']}');
    final mine = (deleted[kind] ??= await db.deletedAt(kind))[uid];
    if (mine != null && !at.isAfter(mine)) continue;
    if (kind == 'product') {
      final p = await db.product(uid);
      if (p != null && p.updatedAt.isAfter(at)) continue;
      if (p != null) await db.deleteProduct(uid);
    } else if (kind == 'supplier') {
      await db.deleteSupplier(uid);
    } else if (kind == 'shop') {
      await db.deleteShop(uid);
    }
    marks.add((kind, uid, at));
    deleted[kind]![uid] = at;
  }
  await db.markDeletedAll(marks);
  final goneProducts = await db.deletedAt('product'), goneSuppliers = await db.deletedAt('supplier'), goneShops = await db.deletedAt('shop');

  final save = <String, CatalogProduct>{}; // saved together at the end: one transaction for the whole file
  final list = m['products'] as List? ?? [];
  // A big file reads the whole catalogue once. A small one (a team sync's few changes) looks
  // each product up by id, and reads the catalogue only for one it doesn't know.
  final byUid = <String, CatalogProduct>{};
  Matcher? match;
  Future<Matcher> matcher() async {
    if (match != null) return match!;
    final ours = await db.products();
    byUid.addAll({for (final p in ours) p.uid: p, ...save});
    return match = Matcher([...ours, ...save.values]);
  }

  if (list.length > 200) await matcher();
  for (final (i, j) in list.indexed) {
    await tell(step, i, list.length, 'Merging', 'products');
    final p = CatalogProduct.fromJson(j as Map);
    final gone = goneProducts[p.uid];
    if (gone != null && !p.updatedAt.isAfter(gone)) continue; // deleted here after its last change
    final here = byUid[p.uid] ?? (match == null ? save[p.uid] ?? await db.product(p.uid) : null) ?? (await matcher()).find(codes: p.allCodes, name: p.name);
    if (here == null) {
      save[p.uid] = byUid[p.uid] = p;
      match?.add(p);
    } else if (p.updatedAt.isAfter(here.updatedAt)) {
      final x = CatalogProduct.fromJson({...p.toJson(), 'uid': here.uid})
        ..kinds.addAll(here.kinds)
        ..sources.addAll(here.sources);
      save[x.uid] = byUid[x.uid] = x;
    }
  }
  if (list.isNotEmpty) step?.value = (text: 'Merging ${list.length} of ${list.length} products', part: 1);
  if (save.length > 500) step?.value = (text: 'Saving ${save.length} products…', part: null);
  await db.saveProducts(save.values.toList(), touch: false);
  products = save.length;

  final have = {for (final x in await db.suppliers()) normName(x.name)};
  for (final r in (m['suppliers'] as List? ?? [])) {
    final x = CatalogSupplier.fromRow(r as Map);
    if (goneSuppliers.containsKey(x.uid)) continue;
    if (have.add(normName(x.name))) {
      await db.saveSupplier(x);
      suppliers++;
    }
  }

  final mine = {for (final s in await db.shops()) s.uid: s};
  for (final r in (m['shops'] as List? ?? [])) {
    final s = Shop.fromRow(r as Map);
    if (goneShops.containsKey(s.uid)) continue;
    final here = mine[s.uid];
    final newer = here == null || (s.lastPull != null && (here.lastPull == null || s.lastPull!.isAfter(here.lastPull!)));
    final newerCode = here != null && s.costCodeAt != null && (here.costCodeAt == null || s.costCodeAt!.isAfter(here.costCodeAt!));
    if (!newer) {
      if (newerCode) {
        await db.saveShop(
          here
            ..costCodeJson = s.costCodeJson
            ..costCodeAt = s.costCodeAt,
        );
        shops++;
      }
      continue;
    }
    if (here != null && !newerCode && here.costCodeAt != null) {
      s
        ..costCodeJson = here.costCodeJson
        ..costCodeAt = here.costCodeAt; // a newer pull elsewhere doesn't undo our newer code
    }
    await db.saveShop(s);
    await db.replaceShopProducts(s.uid, [
      for (final p in (r['products'] as List? ?? [])) {...(p as Map).cast<String, Object?>()}..remove('shop_uid'),
    ]);
    shops++;
  }
  return ImportResult(products, suppliers, shops, received: (m['products'] as List? ?? []).length, changes: m['changes'] as String?);
}
