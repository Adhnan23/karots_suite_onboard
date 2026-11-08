import 'dart:convert';

import 'package:uuid/uuid.dart';

const _uuid = Uuid();
String newUid() => _uuid.v4();

Set<String> _set(Object? s) => (s as String? ?? '').split(',').where((x) => x.isNotEmpty).toSet();

/// A pack of a product (Card ×12): its own price and barcode.
class Pack {
  Pack({required this.name, required this.size, this.selling = '', this.wholesale = '', this.barcode = ''});
  String name, size, selling, wholesale, barcode;
  Map<String, Object?> toMap() => {'name': name, 'size': size, 'selling': selling, 'wholesale': wholesale, 'barcode': barcode};
  factory Pack.fromMap(Map m) => Pack(
    name: m['name'] as String? ?? '',
    size: '${m['size'] ?? ''}',
    selling: m['selling'] as String? ?? '',
    wholesale: m['wholesale'] as String? ?? '',
    barcode: m['barcode'] as String? ?? '',
  );
}

/// What one supplier sells a product for: their own item code, cost and price.
class Offer {
  Offer({required this.supplierUid, required this.supplierName, this.code = '', this.cost = '', this.price = '', DateTime? updatedAt})
    : updatedAt = updatedAt ?? DateTime.now();
  final String supplierUid;
  String supplierName, code, cost, price;
  DateTime updatedAt;
  Map<String, Object?> toMap() => {
    'supplier_uid': supplierUid,
    'supplier_name': supplierName,
    'code': code,
    'cost': cost,
    'price': price,
    'updated_at': updatedAt.toIso8601String(),
  };
  factory Offer.fromMap(Map m) => Offer(
    supplierUid: '${m['supplier_uid']}',
    supplierName: '${m['supplier_name'] ?? ''}',
    code: '${m['code'] ?? ''}',
    cost: '${m['cost'] ?? ''}',
    price: '${m['price'] ?? ''}',
    updatedAt: DateTime.tryParse('${m['updated_at']}'),
  );
}

/// A product in the catalogue. Money is a decimal string. fields: custom field
/// values by field label (Generic name → Paracetamol).
class CatalogProduct {
  CatalogProduct({
    String? uid,
    required this.name,
    this.nameLocal = '',
    this.barcode = '',
    this.category = '',
    this.unit = 'pcs',
    this.cost = '',
    this.selling = '',
    this.wholesale = '',
    this.taxRate = '',
    this.warrantyMonths = 0,
    this.trackSerial = false,
    this.supplier = '',
    Set<String>? kinds,
    Set<String>? sources,
    List<String>? barcodes,
    List<Pack>? packs,
    Map<String, String>? fields,
    List<Offer>? offers,
    DateTime? updatedAt,
  }) : uid = uid ?? newUid(),
       kinds = kinds ?? {},
       sources = sources ?? {},
       barcodes = barcodes ?? [],
       packs = packs ?? [],
       fields = fields ?? {},
       offers = offers ?? [],
       updatedAt = updatedAt ?? DateTime.now();
  final String uid;
  String name, nameLocal, barcode, category, unit, cost, selling, wholesale, taxRate, supplier;
  int warrantyMonths;
  bool trackSerial;
  Set<String> kinds, sources;
  List<String> barcodes;
  List<Pack> packs;
  Map<String, String> fields;

  /// Each supplier's code, cost and price for it.
  List<Offer> offers;
  DateTime updatedAt;

  /// Every code it scans by: the main one and the extras.
  List<String> get allCodes => [if (barcode.isNotEmpty) barcode, ...barcodes];

  Map<String, Object?> toRow() => {
    'uid': uid,
    'name': name,
    'name_local': nameLocal,
    'barcode': barcode,
    'category': category,
    'unit': unit,
    'cost': cost,
    'selling': selling,
    'wholesale': wholesale,
    'tax_rate': taxRate,
    'warranty_months': warrantyMonths,
    'track_serial': trackSerial ? 1 : 0,
    'supplier': supplier,
    'kinds': kinds.join(','),
    'sources': sources.join(','),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory CatalogProduct.fromRow(Map<String, Object?> r) => CatalogProduct(
    uid: r['uid'] as String,
    name: r['name'] as String,
    nameLocal: r['name_local'] as String? ?? '',
    barcode: r['barcode'] as String? ?? '',
    category: r['category'] as String? ?? '',
    unit: r['unit'] as String? ?? 'pcs',
    cost: r['cost'] as String? ?? '',
    selling: r['selling'] as String? ?? '',
    wholesale: r['wholesale'] as String? ?? '',
    taxRate: r['tax_rate'] as String? ?? '',
    warrantyMonths: r['warranty_months'] as int? ?? 0,
    trackSerial: (r['track_serial'] as int? ?? 0) == 1,
    supplier: r['supplier'] as String? ?? '',
    kinds: _set(r['kinds']),
    sources: _set(r['sources']),
    updatedAt: DateTime.tryParse(r['updated_at'] as String? ?? ''),
  );

  /// As JSON (review rows and drafts carry products this way).
  Map<String, Object?> toJson() => {
    ...toRow(),
    'barcodes': barcodes,
    'packs': [for (final k in packs) k.toMap()],
    'fields': fields,
    'offers': [for (final o in offers) o.toMap()],
  };
  factory CatalogProduct.fromJson(Map m) {
    final p = CatalogProduct.fromRow({...m.cast<String, Object?>(), 'uid': m['uid'] ?? newUid()});
    p.barcodes = [for (final b in (m['barcodes'] as List? ?? [])) '$b'];
    p.packs = [for (final k in (m['packs'] as List? ?? [])) Pack.fromMap(k as Map)];
    p.fields = (m['fields'] as Map? ?? {}).map((k, v) => MapEntry('$k', '$v'));
    p.offers = [for (final o in (m['offers'] as List? ?? [])) Offer.fromMap(o as Map)];
    return p;
  }
}

class CatalogSupplier {
  CatalogSupplier({
    String? uid,
    required this.name,
    this.contact = '',
    this.phone = '',
    this.address = '',
    this.creditDays = 0,
    Set<String>? kinds,
    Set<String>? sources,
  }) : uid = uid ?? newUid(),
       kinds = kinds ?? {},
       sources = sources ?? {};
  final String uid;
  String name, contact, phone, address;
  int creditDays;
  Set<String> kinds, sources;
  Map<String, Object?> toRow() => {
    'uid': uid,
    'name': name,
    'contact': contact,
    'phone': phone,
    'address': address,
    'credit_days': creditDays,
    'kinds': kinds.join(','),
    'sources': sources.join(','),
  };
  factory CatalogSupplier.fromRow(Map r) => CatalogSupplier(
    uid: r['uid'] as String? ?? newUid(),
    name: r['name'] as String? ?? '',
    contact: r['contact'] as String? ?? '',
    phone: r['phone'] as String? ?? '',
    address: r['address'] as String? ?? '',
    creditDays: r['credit_days'] as int? ?? 0,
    kinds: _set(r['kinds']),
    sources: _set(r['sources']),
  );
}

/// A shop profile. snapshot holds what the last pull read: plugins, categories,
/// units, Product Plus fields, Alternatives, AI settings, stock-take.
class Shop {
  Shop({
    String? uid,
    required this.name,
    this.kind = '',
    this.address = '',
    this.installId = '',
    this.secretName = '',
    this.lastPull,
    Map<String, dynamic>? snapshot,
  }) : uid = uid ?? newUid(),
       snapshot = snapshot ?? {};
  final String uid;
  String name, kind, address, installId;

  /// Which support secret opens this shop ("" = the first).
  String secretName;
  DateTime? lastPull;
  Map<String, dynamic> snapshot;

  List<String> get plugins => [for (final p in (snapshot['plugins'] as List? ?? [])) '$p'];
  bool has(String plugin) => plugins.contains(plugin);
  bool get viaTailscale {
    final host = Uri.tryParse(address)?.host ?? '';
    return host.endsWith('.ts.net') || RegExp(r'^100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.').hasMatch(host);
  }

  Map<String, Object?> toRow() => {
    'uid': uid,
    'name': name,
    'kind': kind,
    'address': address,
    'install_id': installId,
    'secret_name': secretName,
    'last_pull': lastPull?.toIso8601String(),
    'snapshot': jsonEncode(snapshot),
  };
  factory Shop.fromRow(Map r) => Shop(
    uid: r['uid'] as String,
    name: r['name'] as String,
    kind: r['kind'] as String? ?? '',
    address: r['address'] as String? ?? '',
    installId: r['install_id'] as String? ?? '',
    secretName: r['secret_name'] as String? ?? '',
    lastPull: DateTime.tryParse(r['last_pull'] as String? ?? ''),
    snapshot: (jsonDecode(r['snapshot'] as String? ?? '{}') as Map).cast<String, dynamic>(),
  );
}

/// Something a pull found that the catalogue hasn't got: accept, fix or drop.
class ReviewItem {
  ReviewItem({String? uid, required this.shopUid, required this.kind, required this.data, this.status = 'new'}) : uid = uid ?? newUid();
  final String uid, shopUid, kind; // kind: product | supplier
  Map<String, dynamic> data;
  String status; // new | accepted | dropped
  Map<String, Object?> toRow() => {'uid': uid, 'shop_uid': shopUid, 'kind': kind, 'json': jsonEncode(data), 'status': status};
  factory ReviewItem.fromRow(Map r) => ReviewItem(
    uid: r['uid'] as String,
    shopUid: r['shop_uid'] as String,
    kind: r['kind'] as String,
    data: (jsonDecode(r['json'] as String) as Map).cast<String, dynamic>(),
    status: r['status'] as String,
  );
}

/// Work waiting for a shop to be reachable.
class PendingOp {
  PendingOp({String? uid, required this.shopUid, required this.op, required this.data, this.error = '', DateTime? createdAt})
    : uid = uid ?? newUid(),
      createdAt = createdAt ?? DateTime.now();
  final String uid, shopUid, op; // op: create | update | merge | alt
  Map<String, dynamic> data;
  String error;
  final DateTime createdAt;
  Map<String, Object?> toRow() => {
    'uid': uid,
    'shop_uid': shopUid,
    'op': op,
    'json': jsonEncode(data),
    'error': error,
    'created_at': createdAt.toIso8601String(),
  };
  factory PendingOp.fromRow(Map r) => PendingOp(
    uid: r['uid'] as String,
    shopUid: r['shop_uid'] as String,
    op: r['op'] as String,
    data: (jsonDecode(r['json'] as String) as Map).cast<String, dynamic>(),
    error: r['error'] as String? ?? '',
    createdAt: DateTime.tryParse(r['created_at'] as String? ?? ''),
  );
}
