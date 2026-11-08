import '../data/db.dart';
import '../data/models.dart';
import 'match.dart';

/// Takes a review row into the catalogue (as edited, if it was). A product the
/// catalogue already has by then (accepted from another shop) gains this shop and
/// kind instead of a twin.
Future<void> acceptReview(Db db, String uid, {Map<String, dynamic>? edited}) async {
  final r = (await db.reviews()).firstWhere((x) => x.uid == uid);
  final data = edited ?? r.data;
  if (r.kind == 'supplier') {
    final s = CatalogSupplier.fromRow(data);
    final same = (await db.suppliers()).where((x) => normName(x.name) == normName(s.name)).firstOrNull;
    if (same != null) {
      same.sources.addAll(s.sources);
      same.kinds.addAll(s.kinds);
      await db.saveSupplier(same);
    } else {
      await db.saveSupplier(s);
    }
  } else {
    final p = CatalogProduct.fromJson(data);
    final same = await matchProduct(db, codes: p.allCodes, name: p.name);
    if (same != null) {
      same.sources.addAll(p.sources);
      same.kinds.addAll(p.kinds);
      for (final c in p.allCodes) {
        if (!same.allCodes.contains(c)) same.barcodes.add(c);
      }
      for (final e in p.fields.entries) {
        same.fields.putIfAbsent(e.key, () => e.value);
      }
      await db.saveProduct(same);
    } else {
      await db.saveProduct(p);
    }
  }
  await db.setReview(uid, 'accepted', data);
}

Future<void> dropReview(Db db, String uid) => db.setReview(uid, 'dropped');
