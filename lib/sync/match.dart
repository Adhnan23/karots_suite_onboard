import '../data/db.dart';
import '../data/models.dart';

/// A name as compared: lower case, single spaces, trimmed.
String normName(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

/// The catalogue indexed for a pull: by every barcode, then by name.
class Matcher {
  Matcher(List<CatalogProduct> all) {
    for (final p in all) {
      add(p);
    }
  }
  final _byCode = <String, CatalogProduct>{};
  final _byName = <String, CatalogProduct>{};

  static Future<Matcher> load(Db db) async => Matcher(await db.products());

  void add(CatalogProduct p) {
    for (final c in p.allCodes) {
      _byCode.putIfAbsent(c.trim(), () => p);
    }
    _byName.putIfAbsent(normName(p.name), () => p);
  }

  CatalogProduct? find({required List<String> codes, required String name}) {
    for (final c in codes) {
      final hit = _byCode[c.trim()];
      if (hit != null) return hit;
    }
    return _byName[normName(name)];
  }
}

Future<CatalogProduct?> matchProduct(Db db, {required List<String> codes, required String name}) async =>
    (await Matcher.load(db)).find(codes: codes, name: name);
