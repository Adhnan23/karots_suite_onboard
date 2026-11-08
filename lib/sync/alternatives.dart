import 'match.dart';

class AltMember {
  AltMember(this.productId, this.name);
  final int productId;
  final String name;
}

class AltTier {
  AltTier(this.id, this.name, this.members);
  final int id;
  final String name;
  final List<AltMember> members;
}

/// An Alternatives group as the shop sends it (plugins/alternatives GroupDTO).
class AltGroup {
  AltGroup(this.id, this.name, this.tiers);
  final int id;
  final String name;
  final List<AltTier> tiers;
  factory AltGroup.fromJson(Map m) => AltGroup((m['id'] as num).toInt(), '${m['name']}', [
    for (final t in (m['tiers'] as List? ?? []))
      AltTier(((t as Map)['id'] as num).toInt(), '${t['name']}', [
        for (final x in (t['members'] as List? ?? [])) AltMember(((x as Map)['productId'] as num).toInt(), '${x['name']}'),
      ]),
  ]);
}

/// A tier's members found among another shop's products (from its pull).
({List<int> found, List<String> missing}) matchMembers(AltTier t, List<Map<String, Object?>> shopProducts) {
  final byName = {for (final r in shopProducts) normName('${r['name']}'): (r['remote_id'] as num).toInt()};
  final found = <int>[], missing = <String>[];
  for (final m in t.members) {
    final id = byName[normName(m.name)];
    id == null ? missing.add(m.name) : found.add(id);
  }
  return (found: found, missing: missing);
}
