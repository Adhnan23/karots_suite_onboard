/// One category in the tree, known by its path ("Medicine > Pain").
class CatNode {
  CatNode(this.path, this.name, this.depth);
  final String path, name;
  final int depth;
  final children = <CatNode>[];
  bool get hasChildren => children.isNotEmpty;
}

String _norm(String p) => p.split('>').map((x) => x.trim()).where((x) => x.isNotEmpty).join(' > ');

/// Categories as a tree, built from paths; parents are made when only a child is listed.
class CategoryTree {
  CategoryTree(Iterable<String> paths) {
    for (final p in paths) {
      _ensure(_norm(p));
    }
  }
  final _byPath = <String, CatNode>{};
  final _top = <CatNode>[];

  CatNode? node(String path) => _byPath[_norm(path)];

  CatNode? _ensure(String path) {
    if (path.isEmpty) return null;
    final hit = _byPath[path];
    if (hit != null) return hit;
    final parts = path.split(' > ');
    final parent = parts.length > 1 ? _ensure(parts.sublist(0, parts.length - 1).join(' > ')) : null;
    final n = CatNode(path, parts.last, parts.length - 1);
    _byPath[path] = n;
    final list = parent?.children ?? _top;
    list.add(n);
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return n;
  }

  /// A new category under parent (null = top level); an existing name there is
  /// reused, whatever its case. Returns its path.
  String add(String? parent, String name) {
    final clean = name.trim();
    final siblings = parent == null ? _top : (node(parent)?.children ?? []);
    final same = siblings.where((n) => n.name.toLowerCase() == clean.toLowerCase()).firstOrNull;
    if (same != null) return same.path;
    return _ensure(parent == null ? clean : '${_norm(parent)} > $clean')!.path;
  }

  /// The rows to show: the open branches, or for a search every match with its parents.
  List<CatNode> rows({required Set<String> expanded, String query = ''}) {
    final q = query.trim().toLowerCase();
    final keep = <String>{};
    if (q.isNotEmpty) {
      for (final n in _byPath.values) {
        if (n.name.toLowerCase().contains(q)) {
          final parts = n.path.split(' > ');
          for (var i = 1; i <= parts.length; i++) {
            keep.add(parts.sublist(0, i).join(' > '));
          }
        }
      }
    }
    final out = <CatNode>[];
    void walk(List<CatNode> list) {
      for (final n in list) {
        if (q.isNotEmpty && !keep.contains(n.path)) continue;
        out.add(n);
        if (q.isNotEmpty || expanded.contains(n.path)) walk(n.children);
      }
    }

    walk(_top);
    return out;
  }
}
