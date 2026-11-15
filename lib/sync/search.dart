import '../data/models.dart';

/// Words of a text for searching: lower case, split at anything that isn't a
/// letter or digit and between digits and letters ("500mg" → 500, mg).
List<String> searchWords(String s) => [for (final m in RegExp(r'\d+|[^\W\d_]+', unicode: true).allMatches(s.toLowerCase())) m[0]!];

class _Hay {
  _Hay(CatalogProduct p)
    : name = searchWords('${p.name} ${p.nameLocal}'),
      rest = searchWords([p.category, p.supplier, ...p.fields.values, ...p.allCodes].join(' '));
  final List<String> name, rest;
}

final _hay = Expando<_Hay>();

/// Searches every field (name, local name, category, supplier, custom fields,
/// barcodes). Every word must match some word of the product, by its start or,
/// for words of 4+ letters, with a typo or two. Best first: exact before typo,
/// name before other fields; ties keep the list's order.
List<CatalogProduct> searchProducts(List<CatalogProduct> all, String q) {
  final words = searchWords(q);
  if (words.isEmpty) return List.of(all);
  final hays = [for (final p in all) _hay[p] ??= _Hay(p)];
  // Each distinct product word is checked once per search word, not once per product.
  final vocab = {
    for (final h in hays) ...[...h.name, ...h.rest],
  };
  final kinds = [
    for (final w in words)
      {
        for (final t in vocab)
          if (t.startsWith(w)) t: false else if (_fuzzy(w) && _near(w, t)) t: true,
      },
  ];
  final hits = <(int, int, CatalogProduct)>[];
  for (var i = 0; i < all.length; i++) {
    var worst = 0;
    for (final k in kinds) {
      final s = _score(k, hays[i]);
      if (s > worst) worst = s;
      if (worst > 3) break;
    }
    if (worst <= 3) hits.add((worst, i, all[i]));
  }
  hits.sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
  return [for (final h in hits) h.$3];
}

bool _fuzzy(String w) => w.length >= 4 && !RegExp(r'^\d+$').hasMatch(w);

// k: the product words this search word matches (true = with a typo).
// 0 name, 1 other field, 2 name with a typo, 3 other field with a typo, 4 none.
int _score(Map<String, bool> k, _Hay h) {
  if (h.name.any((t) => k[t] == false)) return 0;
  if (h.rest.any((t) => k[t] == false)) return 1;
  if (h.name.any((t) => k[t] == true)) return 2;
  if (h.rest.any((t) => k[t] == true)) return 3;
  return 4;
}

/// w is within 1 edit (2 for 8+ letters) of the start of t.
bool _near(String w, String t) {
  final k = w.length >= 8 ? 2 : 1;
  if (t.length < w.length - k) return false;
  for (var len = w.length - k; len <= w.length + k; len++) {
    if (len < 1 || len > t.length) continue;
    if (_lev(w, t.substring(0, len), k) <= k) return true;
  }
  return false;
}

int _lev(String a, String b, int max) {
  if ((a.length - b.length).abs() > max) return max + 1;
  var prev = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    var best = i;
    for (var j = 1; j <= b.length; j++) {
      final c = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + c].reduce((x, y) => x < y ? x : y);
      if (cur[j] < best) best = cur[j];
    }
    if (best > max) return max + 1;
    prev = cur;
  }
  return prev[b.length];
}
