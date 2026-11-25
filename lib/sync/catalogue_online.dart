import 'dart:convert';
import 'dart:io' show gzip;

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../data/models.dart';
import '../dupes/find.dart' show squash;
import 'match.dart' show normName;

/// The Karots catalogue published online (the catalogue repo's Publish: `index.json` + `v<N>.json.gz`), the same
/// copy shops' PCs sync. Onboard only ADDS products it doesn't have (user, 2026-11-25): nothing it has is ever
/// changed or removed. Baked in at build time (Makefile: the suite's UPDATE_BASE_URL/CATALOGUE_DIR).
const catalogueAddress = String.fromEnvironment('KAROTS_CATALOGUE_URL');

/// What a catalogue product's own date is: whole seconds, long ago, so the update-file tools
/// (onboard_update.py: ".000" = the catalogue's) never take it for the user's own edit.
final catalogueDate = DateTime(2020, 1, 1);

// The catalogue's duplicate rule (catalogue repo build/dedupe.py words / key): two names are one product when
// their words match, ignoring form and filler words; sizes and every other word count.
const _noise = {
  'tablets',
  'tablet',
  'tabs',
  'tab',
  'capsules',
  'capsule',
  'caps',
  'cap',
  'the',
  'and',
  'of',
  'for',
  'with',
  'pcs',
  'piece',
  'pieces',
  'original',
  'regular',
  'new',
  'bottle',
  'box',
  'jar',
  'tin',
  'pack',
  'packet',
  'pkt',
};
const _unit = {'gm': 'g', 'gms': 'g', 'grams': 'g', 'gram': 'g', 'mls': 'ml', 'ltr': 'l', 'litre': 'l', 'liter': 'l', 'iu': 'iu'};

List<String> catalogueWords(String name) {
  var s = name.replaceAllMapped(RegExp(r'(\d)\s*\+'), (m) => '${m[1]} plus ');
  s = s.toLowerCase().replaceAll('&', ' and ').replaceAll("'", '');
  s = s.replaceAllMapped(RegExp(r'\s*-\s*([a-z])\b'), (m) => '-${m[1]}');
  s = s.replaceAllMapped(RegExp(r'(\d+(?:\.\d+)?)\s*(mg|ml|mls|g|gm|gms|grams?|mcg|iu|kg|l|ltr|litre|liter)\b'), (m) => '${m[1]}${_unit[m[2]] ?? m[2]}');
  return [
    for (final m in RegExp(r'\d+(?:\.\d+)?[a-z]*|[a-z]+(?:-[a-z0-9]+)*').allMatches(s))
      if (!_noise.contains(m[0]))
        (m[0]!.length > 4 && m[0]!.endsWith('s') && !RegExp(r'\d').hasMatch(m[0]![m[0]!.length - 2])) ? m[0]!.substring(0, m[0]!.length - 1) : m[0]!,
  ];
}

/// The set of a name's words, as one string; a name with none (Sinhala, Tamil) is itself.
String catalogueKey(String name) {
  final w = catalogueWords(name).toSet().toList()..sort();
  return w.isEmpty ? normName(name) : w.join(' ');
}

/// Is a product with this name already here? By the catalogue's rule or Onboard's own (squashed name), so a
/// double is never added.
class Have {
  Have(Iterable<String> names) {
    names.forEach(add);
  }
  final _keys = <String>{}, _squashed = <String>{};
  void add(String n) {
    _keys.add(catalogueKey(n));
    final q = squash(n);
    if (q.isNotEmpty) _squashed.add(q);
  }

  bool has(String n) => _keys.contains(catalogueKey(n)) || _squashed.contains(squash(n));
}

/// A published version's products ({id, name, unit, kinds, fields}) that Onboard hasn't got, as Onboard products,
/// in the catalogue's order. Only Onboard's own products count: the catalogue keeps same-name products of two
/// makers apart on purpose, and both come in (as the update files bring them).
List<CatalogProduct> newFromCatalogue(Iterable<String> haveNames, List items) {
  final have = Have(haveNames);
  final out = <CatalogProduct>[];
  for (final x in items) {
    final m = x as Map;
    final name = '${m['name'] ?? ''}'.trim();
    if (name.isEmpty || have.has(name)) continue;
    out.add(
      CatalogProduct(
        name: name,
        unit: '${m['unit'] ?? ''}'.trim().isEmpty ? 'pcs' : '${m['unit']}'.trim(),
        kinds: {
          for (final k in '${m['kinds'] ?? ''}'.split(','))
            if (k.trim().isNotEmpty) k.trim(),
        },
        fields: {
          for (final e in ((m['fields'] as Map?) ?? {}).entries)
            if ('${e.value}'.trim().isNotEmpty) '${e.key}': '${e.value}'.trim(),
        },
        updatedAt: catalogueDate,
      ),
    );
  }
  return out;
}

class CatalogueError implements Exception {
  CatalogueError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The published whole version: checked against the index's SHA-256 and count before anything is used.
({int version, List products}) readVersion(Map index, List<int> gz) {
  final full = index['full'] as Map? ?? {};
  if (sha256.convert(gz).toString() != '${full['sha256']}') throw CatalogueError('The catalogue download is damaged: try again');
  final v = jsonDecode(utf8.decode(gzip.decode(gz))) as Map;
  final products = v['products'] as List? ?? [];
  if (v['version'] != index['version'] || products.length != index['count']) {
    throw CatalogueError('The catalogue online is half-published: try again in a minute');
  }
  return (version: (v['version'] as num).toInt(), products: products);
}

/// Downloads the latest published version.
Future<({int version, List products})> fetchCatalogue({String base = catalogueAddress, http.Client? client}) async {
  if (base.isEmpty) throw CatalogueError('This build has no catalogue address');
  final c = client ?? http.Client();
  try {
    Future<http.Response> get(String name) async {
      final r = await c.get(Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}/$name')).timeout(const Duration(minutes: 2));
      if (r.statusCode != 200) throw CatalogueError('The catalogue online answered ${r.statusCode}');
      return r;
    }

    final index = jsonDecode((await get('index.json')).body) as Map;
    return readVersion(index, (await get('${(index['full'] as Map)['file']}')).bodyBytes);
  } finally {
    if (client == null) c.close();
  }
}
