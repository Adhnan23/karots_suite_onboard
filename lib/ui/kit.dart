import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/backup.dart';

import '../state.dart';
import '../suite/client.dart';
import '../theme/mode.dart';
import '../theme/tokens.dart';

/// Small shared pieces in the Suite's look.

class PageHead extends StatelessWidget {
  const PageHead({super.key, required this.title, this.sub, this.actions = const []});
  final String title;
  final String? sub;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) {
    final c = KsTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                if (sub != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(sub!, style: TextStyle(color: c.mutedForeground)),
                  ),
              ],
            ),
          ),
          ...actions,
          if (_mode(context) case final m?) ModeButton(mode: m),
        ],
      ),
    );
  }
}

class Section extends StatelessWidget {
  const Section({super.key, this.title, required this.children, this.padding = const EdgeInsets.all(14)});
  final String? title;
  final List<Widget> children;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) {
    final c = KsTokens.of(context);
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  title!.toUpperCase(),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .6, color: c.faint),
                ),
              ),
            ...children,
          ],
        ),
      ),
    );
  }
}

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.tone});
  final String text;
  final Color? tone;
  @override
  Widget build(BuildContext context) {
    final c = KsTokens.of(context);
    final t = tone ?? c.mutedForeground;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: t.withValues(alpha: .12), borderRadius: BorderRadius.circular(99)),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: t),
      ),
    );
  }
}

class Empty extends StatelessWidget {
  const Empty({super.key, required this.icon, required this.title, this.sub, this.action});
  final IconData icon;
  final String title;
  final String? sub;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final c = KsTokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(KsTokens.radius)),
              child: Icon(icon, color: c.brand, size: 30),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
              textAlign: TextAlign.center,
            ),
            if (sub != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  sub!,
                  style: TextStyle(color: c.mutedForeground),
                  textAlign: TextAlign.center,
                ),
              ),
            if (action != null) Padding(padding: const EdgeInsets.only(top: 16), child: action!),
          ],
        ),
      ),
    );
  }
}

void toast(BuildContext context, String msg, {bool error = false}) {
  final c = KsTokens.of(context);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg, style: TextStyle(color: error ? Colors.white : c.selectedForeground)),
      backgroundColor: error ? c.danger : c.selected,
    ),
  );
}

String errText(Object e) => e is SuiteError ? e.message : e.toString().replaceFirst('Exception: ', '');

/// Runs [f]; a failure shows as a red toast.
Future<T?> guard<T>(BuildContext context, Future<T> Function() f) async {
  try {
    return await f();
  } catch (e) {
    if (context.mounted) toast(context, errText(e), error: true);
    return null;
  }
}

/// Forms and detail pages stay readable on a wide screen, like the Suite's admin.
class Narrow extends StatelessWidget {
  const Narrow({super.key, required this.child, this.max = 820});
  final Widget child;
  final double max;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: max),
      child: child,
    ),
  );
}

ModeController? _mode(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()?.notifier?.mode;

/// A yes/no before something that can't be taken back.
Future<bool> confirm(BuildContext context, String title, String body, {String yes = 'Delete'}) async =>
    await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(yes)),
        ],
      ),
    ) ==
    true;

/// Over a New product that came back from before: what it is and Start over.
class DraftBar extends StatelessWidget {
  const DraftBar({super.key, required this.onStartOver});
  final VoidCallback onStartOver;
  @override
  Widget build(BuildContext context) {
    final c = KsTokens.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
        child: Row(
          children: [
            Icon(Icons.edit_note_rounded, color: c.foreground),
            const SizedBox(width: 10),
            const Expanded(child: Text('Your unsaved product, kept from before')),
            TextButton(onPressed: onStartOver, child: const Text('Start over')),
          ],
        ),
      ),
    );
  }
}

/// Going back from a product editor: a new product keeps its draft ([keep]);
/// changes to one that exists ask first.
Future<void> leaveEditor(BuildContext context, {required bool changed, void Function()? keep}) async {
  final nav = Navigator.of(context);
  if (keep != null) {
    keep();
    nav.pop();
    return;
  }
  if (!changed || await confirm(context, 'Leave without saving?', 'Your changes to this product will be lost.', yes: 'Discard')) nav.pop();
}

/// A long job's step: its words with numbers, and a bar (moving when it can't
/// tell how far). Shows idle (or nothing) while no job runs.
class StepLine extends StatelessWidget {
  const StepLine(this.step, {super.key, this.idle});
  final ValueListenable<SyncStep?> step;
  final Widget? idle;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<SyncStep?>(
    valueListenable: step,
    builder: (context, v, _) {
      if (v == null) return idle ?? const SizedBox.shrink();
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(v.text, style: TextStyle(fontSize: 13, color: KsTokens.of(context).mutedForeground)),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: v.part),
        ],
      );
    },
  );
}

/// Runs a long job in a dialog that shows its steps with numbers, then closes it.
/// Errors show as guard shows them (null comes back).
Future<T?> withSteps<T>(BuildContext context, String title, Future<T> Function(ValueNotifier<SyncStep?> step) job, {String note = ''}) async {
  final step = ValueNotifier<SyncStep?>(null);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StepLine(step, idle: const LinearProgressIndicator()),
            if (note.isNotEmpty) ...[const SizedBox(height: 14), Text(note)],
          ],
        ),
      ),
    ),
  );
  final r = await guard(context, () => job(step));
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  step.dispose();
  return r;
}
