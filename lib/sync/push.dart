import 'dart:convert';

import '../data/db.dart';
import '../data/models.dart';
import '../flavor.dart';
import '../suite/client.dart';
import 'match.dart';

const stockTakeOff = 'Turn on Stock-take on this shop first';

class PushError implements Exception {
  PushError(this.message);
  final String message;
  @override
  String toString() => message;
}

enum StockMode { none, one, several }

/// One batch of old stock; blank prices follow the product's.
class StockBatch {
  StockBatch({this.qty = '', this.expiry = '', this.cost = '', this.selling = '', this.wholesale = ''});
  String qty, expiry, cost, selling, wholesale;
  Map<String, Object?> toJson() => {'qty': qty, 'expiry': expiry, 'cost': cost, 'selling': selling, 'wholesale': wholesale};
  factory StockBatch.fromJson(Map m) => StockBatch(
    qty: '${m['qty'] ?? ''}',
    expiry: '${m['expiry'] ?? ''}',
    cost: '${m['cost'] ?? ''}',
    selling: '${m['selling'] ?? ''}',
    wholesale: '${m['wholesale'] ?? ''}',
  );
}

/// A product on its way into a shop: the product, its supplier there (the shop's
/// id, or a new one to make, or none), its old stock, and remoteId when it changes
/// a product the shop already has.
class Draft {
  Draft({
    required this.product,
    this.supplierId = 0,
    this.newSupplier,
    this.mode = StockMode.none,
    List<StockBatch>? batches,
    this.remoteId = 0,
    this.aiPick,
    this.useProductSupplier = false,
    this.catalogueItem = 0,
  }) : batches = batches ?? [];
  CatalogProduct product;
  int supplierId, remoteId;
  CatalogSupplier? newSupplier;
  StockMode mode;
  List<StockBatch> batches;

  /// Quick add: the product's usual supplier (from the catalogue) goes with it.
  bool useProductSupplier;

  /// An AI Identify pick, learnt by the shop's AI Assistant on save.
  Map<String, dynamic>? aiPick;

  /// Karots Shelf: the shop's catalogue item this product was picked from (0 = none); it is linked when made.
  int catalogueItem;

  List<StockBatch> get stock => switch (mode) {
    StockMode.none => [],
    StockMode.one => batches.take(1).where((b) => b.qty.trim().isNotEmpty).toList(),
    StockMode.several => batches.where((b) => b.qty.trim().isNotEmpty).toList(),
  };

  Map<String, Object?> toJson() => {
    'product': product.toJson(),
    'supplierId': supplierId,
    'remoteId': remoteId,
    'mode': mode.name,
    'newSupplier': newSupplier?.toRow(),
    'batches': [for (final b in batches) b.toJson()],
    if (catalogueItem > 0) 'catalogueItem': catalogueItem,
  };
  factory Draft.fromJson(Map m) => Draft(
    product: CatalogProduct.fromJson(m['product'] as Map),
    supplierId: (m['supplierId'] as num? ?? 0).toInt(),
    remoteId: (m['remoteId'] as num? ?? 0).toInt(),
    mode: StockMode.values.byName('${m['mode'] ?? 'none'}'),
    newSupplier: m['newSupplier'] == null ? null : CatalogSupplier.fromRow(m['newSupplier'] as Map),
    batches: [for (final b in (m['batches'] as List? ?? [])) StockBatch.fromJson(b as Map)],
    catalogueItem: (m['catalogueItem'] as num? ?? 0).toInt(),
  );
}

/// A catalogue product on its way to a shop: everything but the category, which
/// is the shop's own to choose (Identify in the editor, or its AI Assistant files
/// what lands in Uncategorized).
Draft fromCatalogue(CatalogProduct p) => Draft(product: CatalogProduct.fromJson({...p.toJson(), 'category': ''}));

class FailedBatch {
  FailedBatch(this.index, this.batch, this.message);
  final int index;
  final StockBatch batch;
  final String message;
}

class PushResult {
  PushResult(this.productId, this.failed);
  final int productId;
  final List<FailedBatch> failed;

  /// Packs or barcodes the shop refused (the product and its stock stand).
  final notes = <String>[];
}

/// The unit a shop's new products start with: its default (Units page in the
/// Suite), else pcs (a shop pulled before the Suite had one).
String shopDefaultUnit(Shop s) {
  for (final u in (s.snapshot['units'] as List? ?? [])) {
    if ((u as Map)['isDefault'] == true) return '${u['abbreviation']}';
  }
  return 'pcs';
}

/// A new product for a shop: starts with the shop's default unit.
CatalogProduct newShopProduct(Shop s, {String name = '', String barcode = ''}) => CatalogProduct(name: name, barcode: barcode, unit: shopDefaultUnit(s));

/// The shop's id for the unit (by abbreviation); one it hasn't got is made there.
Future<int> _unitId(SuiteClient c, Db db, Shop s, String unit) async {
  final units = [for (final u in (s.snapshot['units'] as List? ?? [])) u as Map];
  final want = unit.trim().isEmpty ? 'pcs' : unit.trim();
  final hit = units.where((u) => '${u['abbreviation']}'.toLowerCase() == want.toLowerCase()).firstOrNull;
  if (hit != null) return (hit['id'] as num).toInt();
  final made = await c.post('/admin/units', {'name': want, 'abbreviation': want, 'allowDecimal': false}) as Map;
  s.snapshot['units'] = [
    ...units,
    {'id': made['id'], 'name': want, 'abbreviation': want},
  ];
  await db.saveShop(s);
  return (made['id'] as num).toInt();
}

/// The shop's custom field keys for the values held by label.
Map<String, String> fieldValues(Shop s, Map<String, String> byLabel) {
  final out = <String, String>{};
  for (final f in (s.snapshot['fields'] as List? ?? [])) {
    final v = byLabel['${(f as Map)['label']}'];
    if (v != null && v.trim().isNotEmpty) out['${f['key']}'] = v.trim();
  }
  return out;
}

/// The Suite's ProductRequest for this draft (internal/api/dto_catalog.go).
Future<Map<String, Object?>> productBody(Db db, SuiteClient c, Shop s, Draft d, int supplierId, {bool create = true}) async {
  final p = d.product;
  final values = s.has('productplus') ? fieldValues(s, p.fields) : <String, String>{};
  return {
    'name': p.name,
    'nameLocal': p.nameLocal,
    'barcode': p.barcode,
    'categoryId': await c.categoryPath(p.category.trim().isEmpty ? 'Uncategorized' : p.category),
    'unitId': await _unitId(c, db, s, p.unit),
    'costPrice': p.cost,
    'sellingPrice': p.selling,
    'wholesalePrice': p.wholesale,
    'taxRate': p.taxRate,
    if (create) 'reorderLevel': 0, // a change keeps the shop's own level
    'trackSerial': p.trackSerial,
    'warrantyMonths': p.warrantyMonths,
    'supplierId': supplierId,
    'repriceStock': false,
    'dupSourceName': '',
    if (create)
      'packs': [
        for (final k in p.packs) {'name': k.name, 'size': k.size, 'sellingPrice': k.selling, 'wholesalePrice': k.wholesale, 'barcode': k.barcode},
      ],
    if (create) 'barcodes': p.barcodes,
    if (values.isNotEmpty || (create && d.catalogueItem > 0))
      'extra': {
        if (values.isNotEmpty) 'productplus': {'values': values},
        if (create && d.catalogueItem > 0) 'catalogue': {'itemId': d.catalogueItem},
      },
  };
}

/// The shop's id for the draft's supplier; a new one is made once (the shop's list
/// in the snapshot remembers it until the next pull).
Future<int> _supplier(Db db, SuiteClient c, Shop s, Draft d) async {
  final n = d.newSupplier;
  if (n == null) return d.supplierId;
  final list = (s.snapshot['suppliers'] as List?) ?? [];
  final have = list.where((x) => normName('${(x as Map)['name']}') == normName(n.name)).firstOrNull;
  if (have != null) {
    d.supplierId = ((have as Map)['id'] as num).toInt();
    d.newSupplier = null;
    return d.supplierId;
  }
  final r = await c.createSupplier({
    'name': n.name,
    'contact': n.contact,
    'phone': n.phone,
    'address': n.address,
    'creditDays': n.creditDays,
    'openingBalance': '',
  });
  if (!(await db.suppliers()).any((x) => normName(x.name) == normName(n.name))) await db.saveSupplier(n);
  d.supplierId = (r['id'] as num).toInt();
  d.newSupplier = null;
  s.snapshot['suppliers'] = [
    ...list,
    {'id': d.supplierId, 'name': n.name},
  ];
  await db.saveShop(s);
  return d.supplierId;
}

/// Puts a supplier into the shop (once: one it already has is used) and keeps it
/// in the catalogue, marked with this shop and its kind. Returns the shop's id.
Future<int> pushSupplier(Db db, SuiteClient c, Shop s, CatalogSupplier sup) async {
  final id = await _supplier(
    db,
    c,
    s,
    Draft(
      product: CatalogProduct(name: ''),
      newSupplier: sup,
    ),
  );
  final all = await db.suppliers();
  final x = all.where((y) => normName(y.name) == normName(sup.name)).firstOrNull ?? sup;
  x.sources.add(s.uid);
  if (s.kind.isNotEmpty) x.kinds.add(s.kind);
  await db.saveSupplier(x);
  return id;
}

/// Keeps the catalogue's copy (joins the product it matches, or adds it), and
/// the shop's own list, so a pushed product shows there before the next pull.
Future<void> keepCopy(Db db, Shop s, CatalogProduct p, {int remoteId = 0}) async {
  if (isShelf) {
    // Karots Shelf has no catalogue: only the shop's own list.
    if (remoteId > 0) {
      await db.putShopProduct(s.uid, {
        'remote_id': remoteId,
        'catalog_uid': null,
        'name': p.name,
        'barcode': p.barcode,
        'category': p.category,
        'json': jsonEncode(p.toJson()),
      });
    }
    return;
  }
  final hit = await matchProduct(db, codes: p.allCodes, name: p.name);
  final x = hit ?? CatalogProduct.fromJson({...p.toJson(), 'uid': p.uid, 'cost': ''}); // cost is the shop's, never the catalogue's
  if (hit != null) {
    x
      ..name = p.name
      ..category = p.category.isEmpty ? x.category : p.category
      ..selling = p.selling
      ..wholesale = p.wholesale;
    for (final e in p.fields.entries) {
      x.fields[e.key] = e.value;
    }
    if (p.packs.isNotEmpty) x.packs = p.packs;
  }
  if (s.kind.isNotEmpty) x.kinds.add(s.kind);
  x.sources.add(s.uid);
  await db.saveProduct(x);
  if (remoteId > 0) {
    await db.putShopProduct(s.uid, {
      'remote_id': remoteId,
      'catalog_uid': x.uid,
      'name': p.name,
      'barcode': p.barcode,
      'category': p.category,
      'json': jsonEncode({...p.toJson(), 'uid': x.uid}),
    });
  }
}

/// Makes the product in the shop with its first batch, then each further batch.
/// Old stock only (intake): no money, no supplier bill.
Future<PushResult> pushCreate(Db db, SuiteClient c, Shop s, Draft d) async {
  final stock = d.stock;
  if (stock.isNotEmpty && s.snapshot['stockTake'] == false) throw PushError(stockTakeOff);
  if (d.useProductSupplier && d.supplierId == 0 && d.newSupplier == null && d.product.supplier.trim().isNotEmpty) {
    final name = d.product.supplier.trim();
    d.newSupplier = (await db.suppliers()).where((x) => normName(x.name) == normName(name)).firstOrNull ?? CatalogSupplier(name: name);
  }
  final sup = await _supplier(db, c, s, d);
  final body = await productBody(db, c, s, d, sup);
  final first = stock.isEmpty ? null : stock.first;
  Map item;
  try {
    item = await c.intakeCreate(body, quantity: first?.qty ?? '', expiry: first?.expiry ?? '');
  } on SuiteError catch (e) {
    // A pick saved offline whose item left the shop's copy before it got there: made without the link (CTL-13).
    if (d.catalogueItem == 0 || !e.message.contains('catalogue product')) rethrow;
    d.catalogueItem = 0;
    item = await c.intakeCreate(await productBody(db, c, s, d, sup), quantity: first?.qty ?? '', expiry: first?.expiry ?? '');
  }
  final id = (item['productId'] as num).toInt();
  d.remoteId = id;
  // Intake makes the product alone: packs and extra barcodes go on after. One
  // refused is reported, the product stays.
  final notes = <String>[];
  for (final k in d.product.packs) {
    try {
      await c.post('/admin/products/$id/packs', {
        'name': k.name,
        'size': k.size,
        'sellingPrice': k.selling,
        'wholesalePrice': k.wholesale,
        'barcode': k.barcode,
      });
    } on SuiteError catch (e) {
      notes.add('Pack ${k.name}: ${e.message}');
    }
  }
  for (final code in d.product.barcodes) {
    try {
      await c.post('/admin/products/$id/barcodes', {'barcode': code, 'source': 'form'});
    } on SuiteError catch (e) {
      notes.add('Barcode $code: ${e.message}');
    }
  }
  await keepCopy(db, s, d.product, remoteId: id);
  final r = await _batches(c, id, d.product, [
    for (final (i, b) in stock.indexed)
      if (i > 0) (i, b),
  ], sup);
  r.notes.addAll(notes);
  return r;
}

Future<PushResult> _batches(SuiteClient c, int id, CatalogProduct p, List<(int, StockBatch)> todo, int sup) async {
  final failed = <FailedBatch>[];
  for (final (i, b) in todo) {
    try {
      await c.intakeRestock(
        id,
        quantity: b.qty,
        expiry: b.expiry,
        cost: b.cost.isEmpty ? p.cost : b.cost,
        selling: b.selling.isEmpty ? p.selling : b.selling,
        wholesale: b.wholesale.isEmpty ? p.wholesale : b.wholesale,
        supplierId: sup,
      );
    } on SuiteError catch (e) {
      failed.add(FailedBatch(i, b, e.message));
    }
  }
  return _Retry(id, failed, p, sup);
}

class _Retry extends PushResult {
  _Retry(super.productId, super.failed, this.product, this.supplierId);
  final CatalogProduct product;
  final int supplierId;
}

/// Sends again only the batches that were refused.
Future<PushResult> retryBatches(SuiteClient c, PushResult r) {
  final x = r as _Retry;
  return _batches(c, r.productId, x.product, [for (final f in r.failed) (f.index, f.batch)], x.supplierId);
}

/// Changes a product the shop has (name, category, prices, fields…). Packs and
/// extra barcodes are managed in the shop.
Future<void> pushUpdate(Db db, SuiteClient c, Shop s, Draft d) async {
  final sup = await _supplier(db, c, s, d);
  final cur = await c.product(d.remoteId);
  final body = await productBody(db, c, s, d, sup == 0 ? ((cur['supplierId'] as num?)?.toInt() ?? 0) : sup, create: false);
  // A blank price never wipes the shop's own (cost is often left blank here).
  body.removeWhere((k, v) => const {'costPrice', 'sellingPrice', 'wholesalePrice', 'taxRate'}.contains(k) && '$v'.trim().isEmpty);
  await c.updateProduct(d.remoteId, {...cur, ...body});
  // Packs and barcodes go on separately: add what the shop hasn't got (removing
  // one stays a job for the shop's own form).
  final packs = {for (final k in await c.get('/admin/products/${d.remoteId}/packs') as List) '${(k as Map)['name']}'.toLowerCase()};
  for (final k in d.product.packs) {
    if (packs.contains(k.name.toLowerCase())) continue;
    await c.post('/admin/products/${d.remoteId}/packs', {
      'name': k.name,
      'size': k.size,
      'sellingPrice': k.selling,
      'wholesalePrice': k.wholesale,
      'barcode': k.barcode,
    });
  }
  final codes = {for (final b in await c.get('/admin/products/${d.remoteId}/barcodes') as List) '${(b as Map)['barcode']}'};
  for (final code in d.product.barcodes) {
    if (!codes.contains(code)) await c.post('/admin/products/${d.remoteId}/barcodes', {'barcode': code, 'source': 'form'});
  }
  await keepCopy(db, s, d.product, remoteId: d.remoteId);
}

/// A batch of old stock for a product the shop has, kept to push later.
Future<void> queueBatch(Db db, Shop s, int productId, CatalogProduct p, StockBatch b) => db.addPending(
  PendingOp(
    shopUid: s.uid,
    op: 'batches',
    data: {
      'productId': productId,
      'supplierId': 0,
      'product': p.toJson(),
      'batches': [
        {'index': 0, 'batch': b.toJson()},
      ],
    },
  ),
);

/// Disables a product in the shop (the Suite keeps its sales and stock history;
/// it can be enabled again there) and drops it from the shop's list here.
Future<void> disableInShop(Db db, SuiteClient c, Shop s, int remoteId) async {
  await c.delete('/admin/products/$remoteId');
  await db.raw.delete('shop_products', where: 'shop_uid = ? AND remote_id = ?', whereArgs: [s.uid, remoteId]);
}

/// Saves the work for when the shop can be reached.
/// Keeps work for when the shop is in reach; [who] is the Shelf person whose
/// sign-in will send it ('' in Onboard).
Future<void> queue(Db db, Shop s, String op, Draft d, {String who = ''}) => db.addPending(PendingOp(shopUid: s.uid, op: op, data: d.toJson(), who: who));

/// Sends what waited; returns how many are still waiting (each keeps its error).
Future<int> flushPending(Db db, SuiteClient c, Shop s, {String who = ''}) async {
  var left = 0;
  for (final o in await db.pending(s.uid)) {
    if (o.who != who) continue; // another person's: it goes under their own sign-in
    try {
      if (o.op == 'batches') {
        final p = CatalogProduct.fromJson(o.data['product'] as Map);
        final todo = [for (final x in o.data['batches'] as List) ((x['index'] as num).toInt(), StockBatch.fromJson(x['batch'] as Map))];
        final r = await _batches(c, (o.data['productId'] as num).toInt(), p, todo, (o.data['supplierId'] as num? ?? 0).toInt());
        if (r.failed.isNotEmpty) {
          await _keepBatches(db, o, r);
          left++;
          continue;
        }
      } else if (o.op == 'update') {
        await pushUpdate(db, c, s, Draft.fromJson(o.data));
      } else {
        final r = await pushCreate(db, c, s, Draft.fromJson(o.data));
        if (r.failed.isNotEmpty) {
          // The product exists now: only its refused batches wait, never a second create.
          await db.donePending(o.uid);
          await _keepBatches(db, PendingOp(shopUid: o.shopUid, op: 'batches', data: {}, who: o.who), r);
          left++;
          continue;
        }
      }
      await db.donePending(o.uid);
    } catch (e) {
      left++;
      o.error = e is SuiteError ? e.message : '$e';
      await db.addPending(o);
    }
  }
  return left;
}

Future<void> _keepBatches(Db db, PendingOp o, PushResult r) {
  final x = r as _Retry;
  o
    ..data = {
      'productId': r.productId,
      'supplierId': x.supplierId,
      'product': x.product.toJson(),
      'batches': [
        for (final f in r.failed) {'index': f.index, 'batch': f.batch.toJson()},
      ],
    }
    ..error = 'Made in the shop, but ${r.failed.length} batch(es) refused: ${r.failed.first.message}';
  return db.addPending(PendingOp(uid: o.uid, shopUid: o.shopUid, op: 'batches', data: o.data, error: o.error, createdAt: o.createdAt));
}
