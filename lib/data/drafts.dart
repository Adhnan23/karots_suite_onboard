import 'dart:convert';

import '../sync/push.dart';
import 'db.dart';
import 'models.dart';

/// Unsaved new products, so going back doesn't lose them: New product brings the
/// draft back until it's saved or started over. keepDrafts writes them to the
/// database (on leaving an editor, and when the app goes to the background), so a
/// phone that closes the app keeps them too.
CatalogProduct? catalogNewDraft;

/// A shop's unsaved New product, by shop uid, with its supplier choice.
final shopNewDrafts = <String, ({Draft draft, String supplier})>{};

Db? _db;
const _table = 'CREATE TABLE IF NOT EXISTS drafts(key TEXT PRIMARY KEY, json TEXT NOT NULL)';

/// Reads the kept drafts back (at unlock); later keepDrafts calls write to this db.
Future<void> loadDrafts(Db db) async {
  _db = db;
  await db.raw.execute(_table);
  catalogNewDraft = null;
  shopNewDrafts.clear();
  for (final r in await db.raw.query('drafts')) {
    try {
      final key = r['key'] as String, m = jsonDecode(r['json'] as String) as Map;
      if (key == 'catalog') {
        catalogNewDraft = CatalogProduct.fromJson(m);
      } else if (key.startsWith('shop:')) {
        shopNewDrafts[key.substring(5)] = (draft: Draft.fromJson(m['draft'] as Map), supplier: '${m['supplier'] ?? 'none'}');
      }
    } catch (_) {} // an unreadable draft is dropped, never a crash
  }
}

/// Writes every draft as it is now (nothing before loadDrafts).
Future<void> keepDrafts() async {
  final db = _db;
  if (db == null) return;
  final c = catalogNewDraft;
  final shops = {
    for (final e in shopNewDrafts.entries) e.key: jsonEncode({'draft': e.value.draft.toJson(), 'supplier': e.value.supplier}),
  };
  await db.raw.transaction((t) async {
    await t.execute(_table);
    await t.delete('drafts');
    if (c != null) await t.insert('drafts', {'key': 'catalog', 'json': jsonEncode(c.toJson())});
    for (final e in shops.entries) {
      await t.insert('drafts', {'key': 'shop:${e.key}', 'json': e.value});
    }
  });
}
