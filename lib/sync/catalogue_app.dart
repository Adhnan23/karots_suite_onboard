import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/models.dart';

/// Onboard ⇄ the Catalogue app (the catalogue repo's build/app.py; plan docs/plans/onboard-sync.md there). The app
/// is found by its address (IP / Tailscale, port 7710) and signed in with its hourly PIN. Onboard sends its products'
/// names; the app answers each with the catalogue's product (renames and merges followed) or nothing.
class CatalogueApp {
  CatalogueApp(String address, {http.Client? client}) : base = normAddress(address), _c = client ?? http.Client();
  final String base;
  final http.Client _c;
  String _cookie = '';

  /// "192.168.1.5" → "http://192.168.1.5:7710".
  static String normAddress(String a) {
    var s = a.trim().replaceAll(RegExp(r'/+$'), '');
    if (!s.contains('://')) s = 'http://$s';
    final u = Uri.parse(s);
    return u.hasPort ? s : u.replace(port: 7710).toString().replaceAll(RegExp(r'/+$'), '');
  }

  Future<Map> _post(String path, Object body) async {
    final r = await _c
        .post(Uri.parse('$base$path'), headers: {'Content-Type': 'application/json', if (_cookie.isNotEmpty) 'Cookie': _cookie}, body: jsonEncode(body))
        .timeout(const Duration(minutes: 2));
    final j = r.body.isEmpty ? {} : jsonDecode(r.body) as Map;
    if (r.statusCode != 200) {
      throw CatalogueAppError(r.statusCode == 401 ? 'Sign in to the Catalogue app again' : '${j['error'] ?? 'The app answered ${r.statusCode}'}');
    }
    final set = r.headers['set-cookie'] ?? '';
    final m = RegExp(r'ks_cat=([^;]+)').firstMatch(set);
    if (m != null) _cookie = 'ks_cat=${m[1]}';
    return j;
  }

  Future<void> signIn(String pin) => _post('/api/signin', {'pin': pin.trim()});

  /// name → the catalogue's product ({id, name, unit, kinds, fields, selling, barcodes}) or null.
  Future<Map<String, Map?>> match(List<String> names) async {
    final m = (await _post('/api/onboard/match', {'names': names}))['matches'] as Map;
    return {for (final e in m.entries) '${e.key}': e.value == null ? null : (e.value as Map)['product'] as Map};
  }

  Future<Map> up(Map body) => _post('/api/onboard/up', body);
}

class CatalogueAppError implements Exception {
  CatalogueAppError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One thing the catalogue says differently about a product Onboard has: what, Onboard's value, the catalogue's.
typedef Change = ({String what, String mine, String theirs});

/// A catalogue fix to a product Onboard has (name, unit, kinds, a field).
class Fix {
  Fix(this.product, this.changes, this.catalogue);
  final CatalogProduct product;
  final List<Change> changes;
  final Map catalogue;
}

/// The sync's lists. Nothing happens until the person ticks and confirms.
class SyncPlan {
  final fixes = <Fix>[];

  /// Made by hand in Onboard and not in the catalogue: move them there?
  final handMade = <CatalogProduct>[];

  /// Onboard's selling price the catalogue hasn't got (or has another).
  final pricesUp = <({CatalogProduct product, String catalogue})>[];

  /// Onboard's barcodes the catalogue hasn't got.
  final codesUp = <({CatalogProduct product, List<String> codes})>[];

  /// The catalogue's selling price for a product Onboard has none for.
  final pricesDown = <({CatalogProduct product, String selling})>[];

  /// The catalogue's barcodes no Onboard product has yet.
  final codesDown = <({CatalogProduct product, List<String> codes})>[];

  bool get isEmpty => fixes.isEmpty && handMade.isEmpty && pricesUp.isEmpty && codesUp.isEmpty && pricesDown.isEmpty && codesDown.isEmpty;
}

/// Made by the person in Onboard: its date is to the microsecond (".000" = the catalogue's or an update file's;
/// the catalogue repo's onboard_update.py reads it the same way).
bool madeByHand(CatalogProduct p) => !p.updatedAt.toIso8601String().endsWith('.000');

String _kinds(Object? k) => ([
  for (final x in '${k ?? ''}'.split(','))
    if (x.trim().isNotEmpty) x.trim(),
]..sort()).join(', ');

/// Builds the lists from Onboard's products and the app's matches (by name).
SyncPlan planSync(List<CatalogProduct> mine, Map<String, Map?> matches) {
  final plan = SyncPlan();
  final codesHere = {for (final p in mine) ...p.allCodes};
  for (final p in mine) {
    final c = matches[p.name];
    if (c == null) {
      if (madeByHand(p) && p.name.trim().isNotEmpty) plan.handMade.add(p);
      continue;
    }
    final ch = <Change>[];
    void diff(String what, String a, String b) {
      if (b.trim().isNotEmpty && a.trim() != b.trim()) ch.add((what: what, mine: a, theirs: b));
    }

    diff('Name', p.name, '${c['name'] ?? ''}');
    // The catalogue's pcs is "unit not known": a more exact unit here stays (as the update files keep it).
    final unit = '${c['unit'] ?? ''}';
    if (!(unit == 'pcs' && p.unit.trim().isNotEmpty)) diff('Unit', p.unit, unit);
    // Kinds only ever grow (Onboard adds a shop's kind on push): a fix only for a kind the catalogue has and this hasn't.
    final more = [
      for (final k in _kinds(c['kinds']).split(', '))
        if (k.isNotEmpty && !p.kinds.contains(k)) k,
    ];
    if (more.isNotEmpty) ch.add((what: 'Kinds', mine: ([...p.kinds]..sort()).join(', '), theirs: ({...p.kinds, ...more}.toList()..sort()).join(', ')));
    for (final e in ((c['fields'] as Map?) ?? {}).entries) {
      diff('${e.key}', p.fields['${e.key}'] ?? '', '${e.value}');
    }
    if (ch.isNotEmpty) plan.fixes.add(Fix(p, ch, c));

    final theirs = '${c['selling'] ?? ''}'.trim();
    if (p.selling.trim().isNotEmpty && p.selling.trim() != theirs) plan.pricesUp.add((product: p, catalogue: theirs));
    if (p.selling.trim().isEmpty && theirs.isNotEmpty) plan.pricesDown.add((product: p, selling: theirs));
    final theirCodes = [for (final x in (c['barcodes'] as List? ?? [])) '$x'];
    final up = [
      for (final x in p.allCodes)
        if (!theirCodes.contains(x)) x,
    ];
    if (up.isNotEmpty) plan.codesUp.add((product: p, codes: up));
    final down = [
      for (final x in theirCodes)
        if (!codesHere.contains(x)) x,
    ];
    if (down.isNotEmpty) plan.codesDown.add((product: p, codes: down));
  }
  return plan;
}

/// What the app gets for the ticked items. shopOf: the shop(s) a product's price came from.
Map<String, Object> upBody({
  List<CatalogProduct> move = const [],
  List<CatalogProduct> prices = const [],
  List<({CatalogProduct product, List<String> codes})> codes = const [],
  String Function(CatalogProduct)? shopOf,
}) => {
  'add': [
    for (final p in move)
      {
        'name': p.name,
        'unit': p.unit,
        'kinds': [...p.kinds],
        'fields': p.fields,
      },
  ],
  'prices': [
    for (final p in [...move, ...prices])
      if (p.selling.trim().isNotEmpty) {'name': p.name, 'selling': p.selling.trim(), 'shop': shopOf?.call(p) ?? ''},
  ],
  'barcodes': [
    for (final p in move)
      if (p.allCodes.isNotEmpty) {'name': p.name, 'codes': p.allCodes},
    for (final x in codes) {'name': x.product.name, 'codes': x.codes},
  ],
};

/// When Onboard takes something from the catalogue: now, in whole seconds (".000": the catalogue's, as the update
/// files stamp it), so it is the newest for team sync and still not taken for the person's own edit.
DateTime catalogueNow() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day, n.hour, n.minute, n.second);
}

/// A fix taken: only the values the catalogue gives change.
void takeFix(Fix f) {
  final p = f.product, c = f.catalogue;
  for (final x in f.changes) {
    switch (x.what) {
      case 'Name':
        p.name = x.theirs;
      case 'Unit':
        p.unit = x.theirs;
      case 'Kinds':
        p.kinds
          ..clear()
          ..addAll(x.theirs.split(', ').where((k) => k.isNotEmpty));
      default:
        if ((c['fields'] as Map?)?.containsKey(x.what) == true) p.fields[x.what] = x.theirs;
    }
  }
  p.updatedAt = catalogueNow();
}
