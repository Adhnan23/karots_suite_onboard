import '../data/db.dart';
import '../data/models.dart';
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
  }) : batches = batches ?? [];
  CatalogProduct product;
  int supplierId, remoteId;
  CatalogSupplier? newSupplier;
  StockMode mode;
  List<StockBatch> batches;

  /// An AI Identify pick, learnt by the shop's AI Assistant on save.
  Map<String, dynamic>? aiPick;

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
  };
  factory Draft.fromJson(Map m) => Draft(
    product: CatalogProduct.fromJson(m['product'] as Map),
    supplierId: (m['supplierId'] as num? ?? 0).toInt(),
    remoteId: (m['remoteId'] as num? ?? 0).toInt(),
    mode: StockMode.values.byName('${m['mode'] ?? 'none'}'),
    newSupplier: m['newSupplier'] == null ? null : CatalogSupplier.fromRow(m['newSupplier'] as Map),
    batches: [for (final b in (m['batches'] as List? ?? [])) StockBatch.fromJson(b as Map)],
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

int _unitId(Shop s, String unit) {
  final units = [for (final u in (s.snapshot['units'] as List? ?? [])) u as Map];
  Map? find(String a) => units.where((u) => '${u['abbreviation']}'.toLowerCase() == a.toLowerCase()).firstOrNull;
  final u = find(unit.isEmpty ? 'pcs' : unit) ?? find('pcs') ?? units.firstOrNull;
  if (u == null) throw PushError('Pull the shop first: its units aren\'t known');
  return (u['id'] as num).toInt();
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
Future<Map<String, Object?>> productBody(SuiteClient c, Shop s, Draft d, int supplierId, {bool create = true}) async {
  final p = d.product;
  final values = s.has('productplus') ? fieldValues(s, p.fields) : <String, String>{};
  return {
    'name': p.name,
    'nameLocal': p.nameLocal,
    'barcode': p.barcode,
    'categoryId': await c.categoryPath(p.category.trim().isEmpty ? 'Uncategorized' : p.category),
    'unitId': _unitId(s, p.unit),
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
    if (values.isNotEmpty)
      'extra': {
        'productplus': {'values': values},
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

/// Keeps the catalogue's copy: joins the product it matches, or adds it.
Future<void> keepCopy(Db db, Shop s, CatalogProduct p) async {
  final hit = await matchProduct(db, codes: p.allCodes, name: p.name);
  final x = hit ?? CatalogProduct.fromJson({...p.toJson(), 'uid': p.uid});
  if (hit != null) {
    x
      ..name = p.name
      ..category = p.category.isEmpty ? x.category : p.category
      ..cost = p.cost
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
}

/// Makes the product in the shop with its first batch, then each further batch.
/// Old stock only (intake): no money, no supplier bill.
Future<PushResult> pushCreate(Db db, SuiteClient c, Shop s, Draft d) async {
  final stock = d.stock;
  if (stock.isNotEmpty && s.snapshot['stockTake'] == false) throw PushError(stockTakeOff);
  final sup = await _supplier(db, c, s, d);
  final body = await productBody(c, s, d, sup);
  final first = stock.isEmpty ? null : stock.first;
  final item = await c.intakeCreate(body, quantity: first?.qty ?? '', expiry: first?.expiry ?? '');
  final id = (item['productId'] as num).toInt();
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
      await c.post('/admin/products/$id/barcodes', {'barcode': code, 'source': ''});
    } on SuiteError catch (e) {
      notes.add('Barcode $code: ${e.message}');
    }
  }
  await keepCopy(db, s, d.product);
  return _batches(c, id, d.product, [
    for (final (i, b) in stock.indexed)
      if (i > 0) (i, b),
  ], sup);
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
  final body = await productBody(c, s, d, sup == 0 ? ((cur['supplierId'] as num?)?.toInt() ?? 0) : sup, create: false);
  await c.updateProduct(d.remoteId, {...cur, ...body});
  await keepCopy(db, s, d.product);
}

/// Saves the work for when the shop can be reached.
Future<void> queue(Db db, Shop s, String op, Draft d) => db.addPending(PendingOp(shopUid: s.uid, op: op, data: d.toJson()));

/// Sends what waited; returns how many are still waiting (each keeps its error).
Future<int> flushPending(Db db, SuiteClient c, Shop s) async {
  var left = 0;
  for (final o in await db.pending(s.uid)) {
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
          await _keepBatches(db, PendingOp(shopUid: o.shopUid, op: 'batches', data: {}), r);
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
