import '../data/db.dart';
import '../data/models.dart';
import '../sync/match.dart';

class DupPair {
  DupPair(this.a, this.b, this.why);
  final CatalogProduct a, b;
  final String why;
}

const _unitWords = {'mg', 'g', 'kg', 'ml', 'l', 'ltr', 'tab', 'tabs', 'tablet', 'tablets', 'cap', 'caps', 'capsule', 'capsules', 'pcs', 'pc', 'nos'};

/// A name with units, spaces and punctuation gone: "Panadol 500mg Tabs" →
/// "panadol500". Sizes stay, so 500 and 650 never meet.
String squash(String name) {
  final split = normName(name)
      .replaceAllMapped(RegExp(r'(\d)([a-z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAllMapped(RegExp(r'([a-z])(\d)'), (m) => '${m[1]} ${m[2]}');
  return [
    for (final t in split.split(RegExp(r'[^a-z0-9.]+')))
      if (t.isNotEmpty && !_unitWords.contains(t)) t,
  ].join();
}

/// Likely the same product listed twice: a shared barcode, the same name, or the
/// same name once units and spacing are set aside.
List<DupPair> findDupes(List<CatalogProduct> all) {
  final out = <DupPair>[];
  final seen = <String>{};
  void add(CatalogProduct a, CatalogProduct b, String why) {
    if (a.uid == b.uid) return;
    final k = ([a.uid, b.uid]..sort()).join('|');
    if (seen.add(k)) out.add(DupPair(a, b, why));
  }

  final byCode = <String, CatalogProduct>{}, byName = <String, CatalogProduct>{}, bySquash = <String, CatalogProduct>{};
  for (final p in all) {
    for (final c in p.allCodes) {
      final o = byCode[c];
      o == null ? byCode[c] = p : add(o, p, 'same barcode');
    }
    final n = normName(p.name);
    final o = byName[n];
    o == null ? byName[n] = p : add(o, p, 'same name');
    final s = squash(p.name);
    if (s.isEmpty) continue;
    final q = bySquash[s];
    q == null ? bySquash[s] = p : add(q, p, 'same name, written differently');
  }
  return out;
}

/// Folds drop into keep in the catalogue: every barcode, gaps filled, shops and kinds joined.
Future<void> mergeCatalog(Db db, String keepUid, String dropUid) async {
  final keep = (await db.product(keepUid))!, drop = (await db.product(dropUid))!;
  for (final c in drop.allCodes) {
    if (!keep.allCodes.contains(c)) keep.barcode.isEmpty ? keep.barcode = c : keep.barcodes.add(c);
  }
  String fill(String a, String b) => a.trim().isEmpty ? b : a;
  keep
    ..nameLocal = fill(keep.nameLocal, drop.nameLocal)
    ..category = fill(keep.category, drop.category)
    ..cost = fill(keep.cost, drop.cost)
    ..selling = fill(keep.selling, drop.selling)
    ..wholesale = fill(keep.wholesale, drop.wholesale)
    ..supplier = fill(keep.supplier, drop.supplier);
  if (keep.packs.isEmpty) keep.packs = drop.packs;
  for (final e in drop.fields.entries) {
    keep.fields.putIfAbsent(e.key, () => e.value);
  }
  keep.kinds.addAll(drop.kinds);
  keep.sources.addAll(drop.sources);
  await db.saveProduct(keep);
  await db.deleteProduct(dropUid);
  await db.raw.update('shop_products', {'catalog_uid': keepUid}, where: 'catalog_uid = ?', whereArgs: [dropUid]);
}
