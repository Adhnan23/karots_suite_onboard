import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sq;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'models.dart';

/// The app's own SQLite: the catalogue, shop profiles, review and pending work.
class Db {
  Db._(this.raw);
  final Database raw;

  static Future<Db> open([String? path, DatabaseFactory? factory]) => openWith(path: path, factory: factory);

  static Future<Db> openWith({String? path, DatabaseFactory? factory}) async {
    var f = factory;
    if (f == null) {
      if (Platform.isLinux) {
        sqfliteFfiInit();
        f = databaseFactoryFfi;
      } else {
        f = sq.databaseFactory;
      }
    }
    path ??= p.join((await getApplicationSupportDirectory()).path, 'onboard.db');
    final raw = await f.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 2, onCreate: (d, _) => _create(d), onUpgrade: _upgrade),
    );
    return Db._(raw);
  }

  Future<void> close() => raw.close();

  static Future<void> _create(Database d) async {
    for (final s in [
      '''CREATE TABLE catalog_products(uid TEXT PRIMARY KEY, name TEXT NOT NULL, name_local TEXT, barcode TEXT, category TEXT,
         unit TEXT, cost TEXT, selling TEXT, wholesale TEXT, tax_rate TEXT, warranty_months INTEGER, track_serial INTEGER,
         supplier TEXT, kinds TEXT, sources TEXT, updated_at TEXT)''',
      'CREATE TABLE catalog_barcodes(product_uid TEXT NOT NULL, code TEXT NOT NULL, pos INTEGER)',
      'CREATE INDEX catalog_barcodes_code ON catalog_barcodes(code)',
      'CREATE TABLE catalog_packs(product_uid TEXT NOT NULL, name TEXT, size TEXT, selling TEXT, wholesale TEXT, barcode TEXT, pos INTEGER)',
      'CREATE TABLE catalog_fields(product_uid TEXT NOT NULL, label TEXT NOT NULL, value TEXT)',
      '''CREATE TABLE catalog_suppliers(uid TEXT PRIMARY KEY, name TEXT NOT NULL, contact TEXT, phone TEXT, address TEXT,
         credit_days INTEGER, kinds TEXT, sources TEXT)''',
      '''CREATE TABLE shops(uid TEXT PRIMARY KEY, name TEXT NOT NULL, kind TEXT, address TEXT, install_id TEXT,
         last_pull TEXT, snapshot TEXT, secret_name TEXT)''',
      '''CREATE TABLE shop_products(shop_uid TEXT NOT NULL, remote_id INTEGER NOT NULL, catalog_uid TEXT, name TEXT,
         barcode TEXT, category TEXT, json TEXT, PRIMARY KEY(shop_uid, remote_id))''',
      'CREATE TABLE review(uid TEXT PRIMARY KEY, shop_uid TEXT, kind TEXT, key TEXT, json TEXT, status TEXT)',
      'CREATE INDEX review_key ON review(kind, key)',
      'CREATE TABLE pending(uid TEXT PRIMARY KEY, shop_uid TEXT, op TEXT, json TEXT, error TEXT, created_at TEXT)',
    ]) {
      await d.execute(s);
    }
  }

  static Future<void> _upgrade(Database d, int from, int to) async {
    if (from < 2) await d.execute('ALTER TABLE shops ADD COLUMN secret_name TEXT');
  }

  // ---- catalogue products ----

  /// Saves a product; touch: false keeps its own last-changed time (a backup import).
  Future<void> saveProduct(CatalogProduct x, {bool touch = true}) => raw.transaction((t) async {
    if (touch) x.updatedAt = DateTime.now();
    await t.insert('catalog_products', x.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
    for (final tb in ['catalog_barcodes', 'catalog_packs', 'catalog_fields']) {
      await t.delete(tb, where: 'product_uid = ?', whereArgs: [x.uid]);
    }
    for (final (i, c) in x.allCodes.indexed) {
      await t.insert('catalog_barcodes', {'product_uid': x.uid, 'code': c, 'pos': i});
    }
    for (final (i, k) in x.packs.indexed) {
      await t.insert('catalog_packs', {'product_uid': x.uid, ...k.toMap(), 'pos': i});
    }
    for (final e in x.fields.entries) {
      await t.insert('catalog_fields', {'product_uid': x.uid, 'label': e.key, 'value': e.value});
    }
  });

  Future<void> deleteProduct(String uid) => raw.transaction((t) async {
    for (final tb in ['catalog_barcodes', 'catalog_packs', 'catalog_fields']) {
      await t.delete(tb, where: 'product_uid = ?', whereArgs: [uid]);
    }
    await t.delete('catalog_products', where: 'uid = ?', whereArgs: [uid]);
  });

  Future<List<CatalogProduct>> products({String where = '1=1', List<Object?> args = const []}) async {
    final rows = await raw.query('catalog_products', where: where, whereArgs: args, orderBy: 'name COLLATE NOCASE');
    if (rows.isEmpty) return [];
    final out = {for (final r in rows) r['uid'] as String: CatalogProduct.fromRow(r)};
    final ids = out.keys.toList();
    final q = List.filled(ids.length, '?').join(',');
    for (final r in await raw.query('catalog_barcodes', where: 'product_uid IN ($q)', whereArgs: ids, orderBy: 'pos')) {
      final x = out[r['product_uid']]!;
      if (r['code'] != x.barcode) x.barcodes.add(r['code'] as String);
    }
    for (final r in await raw.query('catalog_packs', where: 'product_uid IN ($q)', whereArgs: ids, orderBy: 'pos')) {
      out[r['product_uid']]!.packs.add(Pack.fromMap(r));
    }
    for (final r in await raw.query('catalog_fields', where: 'product_uid IN ($q)', whereArgs: ids)) {
      out[r['product_uid']]!.fields[r['label'] as String] = r['value'] as String? ?? '';
    }
    return out.values.toList();
  }

  Future<CatalogProduct?> product(String uid) async => (await products(where: 'uid = ?', args: [uid])).firstOrNull;

  Future<CatalogProduct?> productByBarcode(String code) async {
    final r = await raw.query('catalog_barcodes', columns: ['product_uid'], where: 'code = ?', whereArgs: [code], limit: 1);
    return r.isEmpty ? null : product(r.first['product_uid'] as String);
  }

  // ---- suppliers ----

  Future<void> saveSupplier(CatalogSupplier s) => raw.insert('catalog_suppliers', s.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
  Future<void> deleteSupplier(String uid) => raw.delete('catalog_suppliers', where: 'uid = ?', whereArgs: [uid]);
  Future<List<CatalogSupplier>> suppliers() async => [
    for (final r in await raw.query('catalog_suppliers', orderBy: 'name COLLATE NOCASE')) CatalogSupplier.fromRow(r),
  ];

  // ---- shops ----

  Future<void> saveShop(Shop s) => raw.insert('shops', s.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
  Future<void> deleteShop(String uid) => raw.delete('shops', where: 'uid = ?', whereArgs: [uid]);
  Future<List<Shop>> shops() async => [for (final r in await raw.query('shops', orderBy: 'name COLLATE NOCASE')) Shop.fromRow(r)];

  // ---- a shop's own list, from its last pull ----

  Future<void> replaceShopProducts(String shopUid, List<Map<String, Object?>> rows) => raw.transaction((t) async {
    await t.delete('shop_products', where: 'shop_uid = ?', whereArgs: [shopUid]);
    for (final r in rows) {
      await t.insert('shop_products', {...r, 'shop_uid': shopUid}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  });

  /// One product in the shop's list, after a push (so it shows before the next pull).
  Future<void> putShopProduct(String shopUid, Map<String, Object?> row) =>
      raw.insert('shop_products', {...row, 'shop_uid': shopUid}, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<Map<String, Object?>>> shopProducts(String shopUid) =>
      raw.query('shop_products', where: 'shop_uid = ?', whereArgs: [shopUid], orderBy: 'name COLLATE NOCASE');

  // ---- review ----

  /// Adds unless that key was already seen (new, accepted or dropped): a dropped row never comes back.
  Future<bool> addReview(ReviewItem r, {String? key}) async {
    final k = key ?? r.uid;
    final seen = await raw.query('review', columns: ['uid'], where: 'kind = ? AND key = ?', whereArgs: [r.kind, k], limit: 1);
    if (seen.isNotEmpty) return false;
    await raw.insert('review', {...r.toRow(), 'key': k});
    return true;
  }

  Future<List<ReviewItem>> reviews({String status = 'new', String? shopUid}) async => [
    for (final r in await raw.query('review', where: shopUid == null ? 'status = ?' : 'status = ? AND shop_uid = ?', whereArgs: [status, ?shopUid]))
      ReviewItem.fromRow(r),
  ];
  Future<void> setReview(String uid, String status, [Map<String, dynamic>? data]) => raw.update(
    'review',
    {'status': status, if (data != null) 'json': ReviewItem(shopUid: '', kind: '', data: data).toRow()['json']},
    where: 'uid = ?',
    whereArgs: [uid],
  );

  // ---- pending ----

  Future<void> addPending(PendingOp o) => raw.insert('pending', o.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
  Future<List<PendingOp>> pending(String shopUid) async => [
    for (final r in await raw.query('pending', where: 'shop_uid = ?', whereArgs: [shopUid], orderBy: 'created_at')) PendingOp.fromRow(r),
  ];
  Future<void> donePending(String uid) => raw.delete('pending', where: 'uid = ?', whereArgs: [uid]);
}
