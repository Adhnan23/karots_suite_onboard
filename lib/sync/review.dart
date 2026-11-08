import '../data/db.dart';
import '../data/models.dart';
import 'match.dart';

/// Takes a review row into the catalogue (as edited, if it was). A product the
/// catalogue already has by then (accepted from another shop) gains this shop and
/// kind instead of a twin.
Future<void> acceptReview(Db db, String uid, {Map<String, dynamic>? edited}) => acceptReviews(db, [uid], edited: edited);

/// Accepts many in one pass: the review list and the catalogue are read once.
Future<void> acceptReviews(Db db, List<String> uids, {Map<String, dynamic>? edited}) async {
  final byUid = {for (final r in await db.reviews()) r.uid: r};
  final match = await Matcher.load(db);
  final suppliers = await db.suppliers();
  for (final uid in uids) {
    final r = byUid[uid];
    if (r == null) continue;
    await _accept(db, r, edited ?? r.data, match, suppliers);
  }
}

Future<void> _accept(Db db, ReviewItem r, Map<String, dynamic> data, Matcher match, List<CatalogSupplier> suppliers) async {
  final uid = r.uid;
  if (r.kind == 'supplier') {
    final s = CatalogSupplier.fromRow(data);
    final same = suppliers.where((x) => normName(x.name) == normName(s.name)).firstOrNull;
    if (same != null) {
      same.sources.addAll(s.sources);
      same.kinds.addAll(s.kinds);
      await db.saveSupplier(same);
    } else {
      await db.saveSupplier(s);
      suppliers.add(s);
    }
  } else {
    final p = CatalogProduct.fromJson(data);
    final same = match.find(codes: p.allCodes, name: p.name);
    if (same != null) {
      same.sources.addAll(p.sources);
      same.kinds.addAll(p.kinds);
      for (final c in p.allCodes) {
        if (!same.allCodes.contains(c)) same.barcodes.add(c);
      }
      for (final e in p.fields.entries) {
        same.fields.putIfAbsent(e.key, () => e.value);
      }
      for (final o in p.offers) {
        same.offers
          ..removeWhere((x) => x.supplierUid == o.supplierUid)
          ..add(o);
      }
      await db.saveProduct(same);
      match.add(same);
    } else {
      await db.saveProduct(p);
      match.add(p);
    }
  }
  await db.setReview(uid, 'accepted', data);
}

Future<void> dropReview(Db db, String uid) => db.setReview(uid, 'dropped');
