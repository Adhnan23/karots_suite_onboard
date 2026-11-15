import 'dart:convert';

import '../data/models.dart';
import 'prompts.dart';

/// One answer: name, category, the hint (specs + explanation) and custom field
/// values by label.
class Candidate {
  Candidate({required this.name, this.category = '', this.specs = '', this.explanation = '', Map<String, String>? fields}) : fields = fields ?? {};
  final String name, category, specs, explanation;
  final Map<String, String> fields;
}

class Identified {
  Identified(this.confident, this.candidates);
  final bool confident;
  final List<Candidate> candidates;
}

List<Map> _fields(Shop s) => [
  for (final f in (s.snapshot['fields'] as List? ?? []))
    if ((f as Map)['isActive'] != false) f,
];
Map _ai(Shop s) => (s.snapshot['ai'] as Map?) ?? const {};

List<Map> _cats(Shop s) => [for (final c in (s.snapshot['categories'] as List? ?? [])) c as Map];

/// "A > B" for each of the shop's categories, by id.
Map<int, String> categoryPaths(Shop s) {
  final cats = _cats(s);
  final name = {for (final c in cats) (c['id'] as num).toInt(): '${c['name']}'};
  return {
    for (final c in cats)
      (c['id'] as num).toInt(): [
        for (final a in (c['path'] as List? ?? [])) name[(a as num).toInt()] ?? '',
        '${c['name']}',
      ].where((x) => x.isNotEmpty).join(' > '),
  };
}

/// The fields ticked in the shop's AI Assistant → Settings → Identify.
List<Map> tickedFields(Shop s) {
  final keys = [for (final k in (_ai(s)['identifyFields'] as List? ?? [])) '$k'];
  return [
    for (final f in _fields(s))
      if (keys.contains('${f['key']}')) f,
  ];
}

/// The whole paste prompt, as the shop would write it (offline).
String identifyPrompt(Shop s, String query, {String barcode = '', String hint = ''}) {
  final ai = _ai(s);
  var system = systemPrompt;
  final naming = '${ai['namingStyle'] ?? ''}'.trim();
  if (naming.isNotEmpty) system += '\n\nPRODUCT NAMING RULES (name the item to match these exactly):\n$naming';
  final custom = '${ai['customPrompt'] ?? ''}'.trim();
  if (custom.isNotEmpty) system += '\n\nADDITIONAL INSTRUCTIONS (follow these strictly):\n$custom';
  final paths = categoryPaths(s);
  final u = StringBuffer('Identify this item: ${query.trim()}');
  if (barcode.trim().isNotEmpty && barcode.trim() != query.trim()) u.write('\nBarcode: ${barcode.trim()}');
  if (hint.trim().isNotEmpty) u.write('\nAdditional context from the shop owner: ${hint.trim()}');
  if (paths.isNotEmpty) {
    final list = (paths.values.toList()..sort()).join('\n- ');
    u.write('\n\nEXISTING shop categories (path — what is in it; reuse a fitting path verbatim, else propose new):\n- $list');
  }
  final ticked = tickedFields(s);
  if (ticked.isNotEmpty) {
    u.write('\n\n$identifyFieldsRule\nFIELDS:\n');
    for (final f in ticked) {
      final type = '${f['type']}';
      final kind = switch (type) {
        'select' => 'dropdown, pick one only: ${(f['options'] as List).join(', ')}',
        'bool' => 'yes/no',
        'textarea' => 'text',
        _ => type,
      };
      final scope = [for (final c in (f['scope'] as List? ?? [])) paths[((c as Map)['id'] as num).toInt()] ?? '${c['name']}'];
      u.write('${f['key']} (${f['label']}, $kind)');
      if (scope.isNotEmpty) u.write(', only for categories: ${scope.join('; ')}');
      u.write('\n');
    }
  }
  return '$system\n\n${u.toString().trimRight()}\n\n$jsonOnly';
}

Map _decode(String reply) {
  final t = reply.trim();
  final i = t.indexOf('{'), j = t.lastIndexOf('}');
  if (i < 0 || j < i) throw const FormatException('That reply has no answer in it — copy the whole reply.');
  return jsonDecode(t.substring(i, j + 1)) as Map;
}

String? _value(Map f, Object? raw) {
  var v = switch (raw) {
    bool b => b ? 'yes' : 'no',
    num n => '$n',
    String x => x.trim(),
    _ => '',
  };
  if (v.isEmpty) return null;
  if (f['type'] == 'select') {
    final opts = [for (final o in (f['options'] as List? ?? [])) '$o'];
    return opts.where((o) => o.toLowerCase() == v.toLowerCase()).firstOrNull;
  }
  return v;
}

/// Reads a pasted chatbot reply (offline): ticked fields that fit the category it gives.
Identified parseIdentify(Shop s, String reply) {
  final m = _decode(reply);
  final ticked = tickedFields(s);
  final byPath = {for (final e in categoryPaths(s).entries) e.value.toLowerCase(): e.key};
  Candidate one(Map c) {
    final cat = '${c['category'] ?? ''}'.replaceAll(' / ', ' > ').split('>').map((x) => x.trim()).where((x) => x.isNotEmpty).join(' > ');
    final catId = byPath[cat.toLowerCase()] ?? 0;
    final values = (c['values'] as Map?) ?? {};
    final out = <String, String>{};
    for (final f in ticked) {
      final scope = [for (final x in (f['scope'] as List? ?? [])) ((x as Map)['id'] as num).toInt()];
      if (!values.containsKey(f['key']) || (scope.isNotEmpty && !scope.contains(catId))) continue;
      final v = _value(f, values[f['key']]);
      if (v != null) out['${f['label']}'] = v;
    }
    return Candidate(name: '${c['name'] ?? ''}'.trim(), category: cat, specs: '${c['specs'] ?? ''}', explanation: '${c['explanation'] ?? ''}', fields: out);
  }

  final confident = m['confident'] == true && '${(m['best'] as Map?)?['name'] ?? ''}'.trim().isNotEmpty;
  final list = confident ? [one(m['best'] as Map)] : [for (final o in (m['options'] as List? ?? [])) one(o as Map)];
  if (list.isEmpty && m['best'] is Map) list.add(one(m['best'] as Map));
  return Identified(confident, list.where((c) => c.name.isNotEmpty).take(4).toList());
}

/// The shop's own Identify answer (connected): fields come back already checked.
Identified fromShopResult(Map r) {
  Candidate one(Map c) => Candidate(
    name: '${c['name'] ?? ''}',
    category: '${c['category'] ?? ''}',
    specs: '${c['specs'] ?? ''}',
    explanation: '${c['explanation'] ?? ''}',
    fields: {for (final f in (c['fields'] as List? ?? [])) '${(f as Map)['label']}': '${f['value']}'},
  );
  final confident = r['confident'] == true;
  return Identified(confident, confident ? [one(r['best'] as Map)] : [for (final o in (r['options'] as List? ?? [])) one(o as Map)]);
}
