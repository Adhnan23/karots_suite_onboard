import 'package:flutter/material.dart';

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
