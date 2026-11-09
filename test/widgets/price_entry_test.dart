import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/data/models.dart';
import 'package:karots_suite_onboard/screens/lots_section.dart';
import 'package:karots_suite_onboard/screens/quick_add_screen.dart';
import 'package:karots_suite_onboard/screens/stock_editor.dart';
import 'package:karots_suite_onboard/sync/push.dart';
import 'package:karots_suite_onboard/theme/app_theme.dart';

import '../cost_code_test.dart' show example;

/// A page with one button that opens [open]; what it returns lands in [got].
Widget opener(Future<Object?> Function(BuildContext) open, void Function(Object?) got) => MaterialApp(
  theme: ksTheme(Brightness.light, fonts: false),
  home: Scaffold(
    body: Builder(
      builder: (c) => TextButton(onPressed: () async => got(await open(c)), child: const Text('open')),
    ),
  ),
);

Finder box(String label) => find.widgetWithText(TextField, label);

void main() {
  testWidgets('Quick add: a coded box price ÷ how many gives one piece; quantity stays as typed', (t) async {
    Object? got;
    await t.pumpWidget(
      opener(
        (c) => quickAddSheet(
          c,
          CatalogProduct(name: 'Panadol'),
          shopName: 'Big',
          code: example,
        ),
        (v) => got = v,
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.enterText(box('Cost price'), 'ESX');
    await t.enterText(box('Selling price'), '300');
    await t.enterText(box('÷ how many'), '10');
    await t.enterText(box('Quantity'), '5');
    await t.tap(find.text('Add to Big'));
    await t.pumpAndSettle();
    final v = got as ({String cost, String price, String qty, String expiry});
    expect((v.cost, v.price, v.qty), ('23', '30', '5'));
  });

  testWidgets('Quick add: a cost the code can\'t read keeps the sheet open', (t) async {
    Object? got = 'not closed';
    await t.pumpWidget(
      opener(
        (c) => quickAddSheet(
          c,
          CatalogProduct(name: 'Panadol'),
          shopName: 'Big',
          code: example,
        ),
        (v) => got = v,
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.enterText(box('Cost price'), 'ESQ');
    await t.tap(find.text('Add to Big'));
    await t.pumpAndSettle();
    expect(got, 'not closed');
    expect(find.text("'q' isn't in this shop's code"), findsOneWidget);
  });

  testWidgets('a batch cost in the code saves its number; a wrong letter is a problem', (t) async {
    final key = GlobalKey<StockEditorState>();
    final d = Draft(
      product: CatalogProduct(name: 'Panadol'),
      mode: StockMode.several,
      batches: [
        StockBatch(qty: '1'),
        StockBatch(qty: '2'),
      ],
    ); // a batch has its own cost box from the second one on
    await t.pumpWidget(
      MaterialApp(
        theme: ksTheme(Brightness.light, fonts: false),
        home: Scaffold(
          body: SingleChildScrollView(
            child: StockEditor(key: key, draft: d, code: example),
          ),
        ),
      ),
    );
    await t.enterText(find.widgetWithText(TextField, 'Cost (blank = product\'s)'), 'ESX');
    await t.pumpAndSettle();
    expect(key.currentState!.problem(), isNull);
    key.currentState!.apply();
    expect(d.batches.last.cost, '230');
    await t.enterText(find.widgetWithText(TextField, 'Cost (blank = product\'s)'), 'ESQ');
    await t.pumpAndSettle();
    expect(key.currentState!.problem(), "'q' isn't in this shop's code");
  });

  testWidgets('a lot\'s cost in the code saves its number; a wrong letter keeps the dialog open', (t) async {
    Object? got = 'not closed';
    await t.pumpWidget(opener((c) => lotForm(c, 'Add a batch', code: example), (v) => got = v));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.enterText(box('Quantity'), '4');
    await t.enterText(box('Cost (blank = the product\'s)'), 'ESQ');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(got, 'not closed');
    await t.enterText(box('Cost (blank = the product\'s)'), 'ESX');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect((got as Map)['cost'], '230');
  });
}
