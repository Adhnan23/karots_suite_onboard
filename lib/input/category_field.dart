import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'category_tree.dart';

/// The shop's category, picked from its own tree like the Suite's product form:
/// search, open and close branches, add a sub-category (+) or a top-level one.
/// Blank = Uncategorized, for the shop to file.
class CategoryField extends StatelessWidget {
  const CategoryField({super.key, required this.controller, required this.paths});
  final TextEditingController controller;
  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    final c = KsTokens.of(context);
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, v, _) => InkWell(
        borderRadius: BorderRadius.circular(KsTokens.radiusSm),
        onTap: () async {
          final picked = await showModalBottomSheet<String>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (_) => _Sheet(paths: paths, value: v.text),
          );
          if (picked != null) controller.text = picked;
        },
        child: InputDecorator(
          decoration: const InputDecoration(labelText: 'Category', suffixIcon: Icon(Icons.expand_more_rounded)),
          isEmpty: false,
          child: Text(
            v.text.isEmpty ? 'Uncategorized: the shop files it' : v.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: v.text.isEmpty ? c.faint : c.foreground),
          ),
        ),
      ),
    );
  }
}

class _Sheet extends StatefulWidget {
  const _Sheet({required this.paths, required this.value});
  final List<String> paths;
  final String value;
  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> {
  late final tree = CategoryTree([...widget.paths, if (widget.value.isNotEmpty) widget.value]);
  late final expanded = <String>{
    // the chosen one's branch starts open
    for (final (i, _) in widget.value.split(' > ').indexed) widget.value.split(' > ').sublist(0, i + 1).join(' > '),
  };
  String q = '';
  String? adding; // the parent being added under; '' = top level
  final name = TextEditingController();

  void add() {
    if (name.text.trim().isEmpty) return;
    Navigator.pop(context, tree.add(adding!.isEmpty ? null : adding, name.text));
  }

  Widget createRow(int depth) => Padding(
    padding: EdgeInsets.fromLTRB(12.0 + depth * 20, 4, 4, 4),
    child: Row(
      children: [
        const Icon(Icons.subdirectory_arrow_right_rounded, size: 18),
        const SizedBox(width: 6),
        Expanded(
          child: TextField(
            controller: name,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Name'),
            onSubmitted: (_) => add(),
          ),
        ),
        const SizedBox(width: 6),
        FilledButton(onPressed: add, child: const Text('Add')),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = KsTokens.of(context);
    final rows = tree.rows(expanded: expanded, query: q);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search categories'),
                onChanged: (v) => setState(() => q = v),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  if (q.isEmpty) _row(context, null, selected: widget.value.isEmpty, label: 'Uncategorized: the shop files it'),
                  for (final n in rows) ...[_row(context, n, selected: n.path == widget.value), if (adding == n.path) createRow(n.depth + 1)],
                  if (rows.isEmpty && q.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No category matches “$q”.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.faint),
                      ),
                    ),
                  if (adding == '') createRow(0),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() {
                      adding = '';
                      name.text = q;
                    }),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('New top-level category'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, CatNode? n, {required bool selected, String? label}) {
    final c = KsTokens.of(context);
    final open = n != null && (q.isNotEmpty || expanded.contains(n.path));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected ? c.selected : Colors.transparent,
        borderRadius: BorderRadius.circular(KsTokens.radiusSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(KsTokens.radiusSm),
          onTap: () => Navigator.pop(context, n?.path ?? ''),
          child: Padding(
            padding: EdgeInsets.only(left: 4.0 + (n?.depth ?? 0) * 20),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  height: 44,
                  child: n != null && n.hasChildren
                      ? IconButton(
                          tooltip: open ? 'Close' : 'Open',
                          icon: Icon(
                            open ? Icons.expand_more_rounded : Icons.chevron_right_rounded,
                            color: selected ? c.selectedForeground : c.mutedForeground,
                          ),
                          onPressed: q.isNotEmpty ? null : () => setState(() => open ? expanded.remove(n.path) : expanded.add(n.path)),
                        )
                      : null,
                ),
                Expanded(
                  child: Text(
                    label ?? n!.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: n != null && n.depth == 0 ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? c.selectedForeground : (n == null ? c.mutedForeground : c.foreground),
                    ),
                  ),
                ),
                if (n != null)
                  IconButton(
                    tooltip: 'Add under ${n.name}',
                    icon: Icon(Icons.add_rounded, size: 20, color: selected ? c.selectedForeground : c.faint),
                    onPressed: () => setState(() {
                      adding = n.path;
                      name.clear();
                      expanded.add(n.path);
                    }),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
