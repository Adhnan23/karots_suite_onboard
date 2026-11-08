import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/data/models.dart';
import 'package:karots_suite_onboard/input/barcodes_editor.dart';
import 'package:karots_suite_onboard/sync/variant.dart';
import 'package:karots_suite_onboard/theme/app_theme.dart';

void main() {
  testWidgets('barcodes: add one at a time, no repeats, remove', (t) async {
    final key = GlobalKey<BarcodesEditorState>();
    await t.pumpWidget(
      MaterialApp(
        theme: ksTheme(Brightness.light, fonts: false),
        home: Scaffold(
          body: BarcodesEditor(key: key, codes: const ['111']),
        ),
      ),
    );
    expect(find.text('111'), findsOneWidget);
    for (final c in ['222', '222', ' 333 ']) {
      await t.enterText(find.widgetWithText(TextField, 'Add a barcode'), c);
      await t.tap(find.byTooltip('Add'));
      await t.pump();
    }
    expect(key.currentState!.codes, ['111', '222', '333']);
    await t.tap(find.byTooltip('Remove 111'));
    await t.pump();
    expect(key.currentState!.codes, ['222', '333']);
    await t.pump(const Duration(seconds: 2)); // let the chips' tooltips settle
  });

  test('a copy for a flavour or size: everything but the identity', () {
    final p = CatalogProduct(
      name: 'Milo 400g',
      barcode: '1',
      barcodes: ['2'],
      cost: '900',
      selling: '1050',
      kinds: {'grocery'},
      packs: [Pack(name: 'Box', size: '12', barcode: 'B1')],
      fields: {'Brand': 'Nestlé'},
    );
    final c = copyAsVariant(p);
    expect(c.uid, isNot(p.uid));
    expect(c.name, 'Milo 400g (copy)');
    expect(c.allCodes, isEmpty);
    expect(c.packs.single.barcode, '');
    expect((c.cost, c.selling, c.fields['Brand']), ('900', '1050', 'Nestlé'));
    expect(c.kinds, {'grocery'});
  });
}
