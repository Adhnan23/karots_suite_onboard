import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ai/identify.dart';
import '../data/models.dart';
import '../state.dart';
import '../suite/client.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';
import 'product_form.dart';

/// ✨ Identify in the editor. Connected: the shop's own Identify (its settings and
/// key); in paste mode it hands back a prompt to copy. Offline: the same prompt
/// built from the pulled settings. A pick fills name, category and fields.
Widget identifyButton(BuildContext context, Shop shop, GlobalKey<ProductFormState> form) => FilledButton.tonalIcon(
  onPressed: () {
    final f = form.currentState;
    if (f == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _IdentifySheet(shop: shop, form: f, app: AppScope.of(context)),
    );
  },
  icon: const Icon(Icons.auto_awesome_rounded),
  label: const Text('Identify'),
);

class _IdentifySheet extends StatefulWidget {
  const _IdentifySheet({required this.shop, required this.form, required this.app});
  final Shop shop;
  final ProductFormState form;
  final AppState app;
  @override
  State<_IdentifySheet> createState() => _IdentifySheetState();
}

class _IdentifySheetState extends State<_IdentifySheet> {
  late final query = TextEditingController(text: widget.form.name.text.trim().isNotEmpty ? widget.form.name.text.trim() : widget.form.barcode.text.trim());
  final reply = TextEditingController();
  String prompt = '';
  Identified? result;
  bool busy = false;
  String error = '';
  SuiteClient? get client => widget.app.session(widget.shop);

  Map<String, dynamic> get ask => {'query': query.text.trim(), 'barcode': widget.form.barcode.text.trim(), 'hint': '', 'short': false};

  Future<void> start() async {
    if (query.text.trim().isEmpty) return;
    setState(() {
      busy = true;
      error = '';
      result = null;
    });
    try {
      if (client != null && widget.shop.has('aicatalog')) {
        final r = await client!.identify(ask);
        _take(r);
      } else {
        prompt = identifyPrompt(widget.shop, query.text.trim(), barcode: widget.form.barcode.text.trim());
      }
    } catch (e) {
      error = errText(e);
    }
    setState(() => busy = false);
  }

  void _take(Map r) {
    if (r['result'] != null) {
      result = fromShopResult(r['result'] as Map);
      prompt = '';
    } else {
      prompt = '${r['prompt'] ?? ''}';
    }
    if ('${r['error'] ?? ''}'.isNotEmpty) error = '${r['error']}';
  }

  Future<void> read() async {
    setState(() => busy = true);
    try {
      if (client != null && widget.shop.has('aicatalog')) {
        _take(await client!.identify({...ask, 'reply': reply.text}));
      } else {
        result = parseIdentify(widget.shop, reply.text);
        prompt = '';
      }
      error = '';
    } catch (e) {
      error = errText(e);
    }
    setState(() => busy = false);
  }

  void use(Candidate c) {
    widget.form.fill(
      name: c.name,
      category: c.category,
      fieldValues: c.fields,
      pick: {
        'name': c.name,
        'category': c.category,
        'specs': c.specs,
        'explanation': c.explanation,
        'source': result!.confident ? 'ai_confident' : 'user_picked',
        'query': query.text.trim(),
      },
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final k = KsTokens.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .8,
        child: ListView(
          children: [
            const Text('Identify', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text(
              client != null ? 'Asks ${widget.shop.name}\'s AI Assistant, with its settings' : 'Offline: copy the prompt to a chatbot, paste its answer back',
              style: TextStyle(color: k.mutedForeground),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: query,
                    decoration: const InputDecoration(labelText: 'What was typed or scanned'),
                    onSubmitted: (_) => start(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: busy ? null : start, child: Text(busy ? '…' : 'Ask')),
              ],
            ),
            if (error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(error, style: TextStyle(color: k.danger)),
              ),
            if (prompt.isNotEmpty) ...[
              const SizedBox(height: 14),
              Section(
                title: 'Prompt',
                children: [
                  Text(
                    prompt,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: k.mutedForeground),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: prompt));
                      if (context.mounted) toast(context, 'Prompt copied: paste it into Gemini or ChatGPT');
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copy prompt'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: reply,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Chatbot answer'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () async {
                          final d = await Clipboard.getData('text/plain');
                          if (d?.text != null) setState(() => reply.text = d!.text!);
                        },
                        icon: const Icon(Icons.content_paste_rounded),
                        label: const Text('Paste'),
                      ),
                      const Spacer(),
                      FilledButton(onPressed: busy || reply.text.trim().isEmpty ? null : read, child: const Text('Read answer')),
                    ],
                  ),
                ],
              ),
            ],
            if (result != null) ...[
              const SizedBox(height: 14),
              Text(
                result!.confident ? 'THE AI IS SURE' : 'NOT SURE: ${result!.candidates.length} OPTIONS',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: k.faint),
              ),
              const SizedBox(height: 6),
              for (final c in result!.candidates)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                              ),
                              FilledButton(onPressed: () => use(c), child: const Text('Use this')),
                            ],
                          ),
                          if (c.category.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Tag(c.category)),
                          if (c.explanation.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(c.explanation)),
                          if (c.specs.isNotEmpty) Text(c.specs, style: TextStyle(color: k.faint, fontSize: 12)),
                          for (final e in c.fields.entries) Text('${e.key}: ${e.value}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
