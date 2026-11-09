import 'package:flutter/material.dart';

import '../input/cost_code.dart';
import '../theme/tokens.dart';

/// Type a shop's cost code from its cheat sheet: the letters for each digit (a
/// digit may have several, e.g. 0 = ix). Returns the new code (empty after
/// Clear), or null when closed.
Future<CostCode?> editCostCode(BuildContext context, CostCode current) {
  final boxes = [for (var d = 0; d < 10; d++) TextEditingController(text: current.letters[d] ?? '')];
  CostCode code() => CostCode({for (var d = 0; d < 10; d++) d: boxes[d].text});
  return showModalBottomSheet<CostCode>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final problem = code().problem();
        Widget box(int d) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextField(
            controller: boxes[d],
            textCapitalization: TextCapitalization.none,
            decoration: InputDecoration(labelText: '$d'),
            onChanged: (_) => set(() {}),
          ),
        );
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Cost code', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                Text(
                  'The letters this shop writes for each digit, from its cheat sheet. '
                  'A digit can have more than one (0 = ix).',
                  style: TextStyle(color: KsTokens.of(ctx).mutedForeground, fontSize: 13),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Column(children: [for (var d = 0; d < 5; d++) box(d)])),
                    const SizedBox(width: 10),
                    Expanded(child: Column(children: [for (var d = 5; d < 10; d++) box(d)])),
                  ],
                ),
                if (problem != null) Text(problem, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    TextButton(onPressed: () => Navigator.pop(ctx, CostCode({})), child: const Text('Clear')),
                    const Spacer(),
                    FilledButton(onPressed: problem != null ? null : () => Navigator.pop(ctx, code()), child: const Text('Save')),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
