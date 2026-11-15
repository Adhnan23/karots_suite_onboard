import 'package:flutter/material.dart';

import '../settings/secure.dart';

/// Fields a person can hide on a shop's product page, this device only. Hidden
/// fields keep their values (a catalogue pick's packs still go to the shop).
const optionalFields = ['Local name', 'Other barcodes', 'Wholesale price', 'Warranty months', 'Packs', 'More details'];
const _key = 'hidden_fields';

final hiddenFields = ValueNotifier<Set<String>>({});
bool _loaded = false;

Future<void> loadHiddenFields(KeyStore store) async {
  if (_loaded) return;
  _loaded = true;
  hiddenFields.value = {...?(await store.read(_key))?.split('|').where(optionalFields.contains)};
}

Future<void> showFieldsSheet(BuildContext context, KeyStore store) => showModalBottomSheet(
  context: context,
  showDragHandle: true,
  builder: (_) => ValueListenableBuilder(
    valueListenable: hiddenFields,
    builder: (_, hidden, _) => ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        const ListTile(
          title: Text('Fields to show', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('On this device. Hidden fields keep what they have.'),
        ),
        for (final f in optionalFields)
          SwitchListTile(
            title: Text(f),
            value: !hidden.contains(f),
            onChanged: (on) {
              hiddenFields.value = on ? ({...hidden}..remove(f)) : {...hidden, f};
              store.write(_key, hiddenFields.value.join('|'));
            },
          ),
      ],
    ),
  ),
);
