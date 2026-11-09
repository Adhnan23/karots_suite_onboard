import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/data/models.dart';
import 'package:karots_suite_onboard/input/price_fields.dart';
import 'package:karots_suite_onboard/screens/product_form.dart';
import 'package:karots_suite_onboard/theme/app_theme.dart';

import '../cost_code_test.dart' show example;

Widget host(Widget child) => MaterialApp(
  theme: ksTheme(Brightness.light, fonts: false),
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
);

Finder box(String label) => find.widgetWithText(TextField, label);
String text(WidgetTester t, String label) => t.widget<TextField>(box(label)).controller!.text;

void main() {
  testWidgets('a coded cost shows its number; a wrong letter shows the error', (t) async {
    final key = GlobalKey<PriceFieldsState>();
    await t.pumpWidget(host(PriceFields(key: key, cost: '', selling: '', code: example)));
    await t.enterText(box('Cost price'), 'E');
    await t.pumpAndSettle();
    expect(text(t, 'Cost price'), '2', reason: 'a letter turns into its digit as it is typed');
    await t.enterText(box('Cost price'), '2SX');
    await t.pumpAndSettle();
    expect(text(t, 'Cost price'), '230');
    expect(find.text('ESX'), findsOneWidget, reason: 'the letters typed show under the number, to check them');
    final f = t.widget<TextField>(box('Cost price'));
    expect((f.enableSuggestions, f.autocorrect, f.keyboardType), (false, false, TextInputType.visiblePassword),
        reason: 'no keyboard word-building, or its suggestions show the letters mixed up');
    await t.enterText(box('Cost price'), 'ESQ');
    await t.pumpAndSettle();
    expect(find.text("'q' isn't in this shop's code"), findsOneWidget);
    expect(key.currentState!.read().error, "'q' isn't in this shop's code");
  });

  testWidgets('markup fills the selling price', (t) async {
    await t.pumpWidget(host(PriceFields(cost: '', selling: '')));
    await t.enterText(box('Cost price'), '200');
    await t.enterText(box('Markup ×'), '1.15');
    await t.pumpAndSettle();
    expect(text(t, 'Selling price'), '230');
  });

  testWidgets('÷ how many gives the price of one', (t) async {
    final key = GlobalKey<PriceFieldsState>();
    await t.pumpWidget(host(PriceFields(key: key, cost: '', selling: '', code: example)));
    await t.enterText(box('Cost price'), 'ESX');
    await t.enterText(box('Selling price'), '300');
    await t.enterText(box('÷ how many'), '10');
    await t.pumpAndSettle();
    final r = key.currentState!.read();
    expect((r.cost, r.selling, r.error), ('23', '30', null));
    expect(find.text('ESX  = 23 each'), findsOneWidget, reason: 'the letters stay visible with the price of one');
    expect(find.text('= 30 each'), findsOneWidget);
  });

  testWidgets('an existing product opens with its markup and saves exactly what it had', (t) async {
    final key = GlobalKey<PriceFieldsState>();
    await t.pumpWidget(host(PriceFields(key: key, cost: '23', selling: '30')));
    expect(text(t, 'Markup ×'), '1.3');
    expect(text(t, '÷ how many'), '');
    await t.pumpAndSettle();
    final r = key.currentState!.read();
    expect((r.cost, r.selling), ('23', '30'));
  });

  testWidgets('without a code (Shelf) the cost box is a number box with no decoding', (t) async {
    await t.pumpWidget(host(PriceFields(cost: '', selling: '')));
    expect(t.widget<TextField>(box('Cost price')).keyboardType, const TextInputType.numberWithOptions(decimal: true));
    await t.enterText(box('Cost price'), 'ESX');
    await t.pumpAndSettle();
    expect(find.text('= 230'), findsNothing);
  });

  testWidgets('the product form saves the decoded, divided cost and names an unreadable one', (t) async {
    final key = GlobalKey<ProductFormState>();
    await t.pumpWidget(
      host(
        SingleChildScrollView(
          child: ProductForm(
            key: key,
            product: CatalogProduct(name: 'Panadol'),
            costCode: example,
          ),
        ),
      ),
    );
    await t.enterText(box('Cost price'), 'ESX');
    await t.enterText(box('Selling price'), '300');
    await t.enterText(box('÷ how many'), '10');
    await t.pumpAndSettle();
    expect(key.currentState!.problem(), isNull);
    final p = key.currentState!.read();
    expect((p.cost, p.selling), ('23', '30'));
    await t.enterText(box('Cost price'), 'ESQ');
    await t.pumpAndSettle();
    expect(key.currentState!.problem(), "'q' isn't in this shop's code");
  });

  testWidgets('a bad ÷ never blanks the prices read() gives; a draft keeps what was typed', (t) async {
    final key = GlobalKey<ProductFormState>();
    await t.pumpWidget(
      host(
        SingleChildScrollView(
          child: ProductForm(key: key, product: CatalogProduct(name: 'Panadol', cost: '9.50', selling: '12'), costCode: example),
        ),
      ),
    );
    await t.enterText(box('÷ how many'), '1.2.3');
    await t.pumpAndSettle();
    expect(key.currentState!.problem(), 'How many must be a number');
    final p = key.currentState!.read();
    expect((p.cost, p.selling), ('9.50', '12'));
    await t.enterText(box('Cost price'), 'ESQ');
    await t.enterText(box('Selling price'), '30');
    await t.pumpAndSettle();
    final d = key.currentState!.readDraft();
    expect((d.cost, d.selling), ('ESQ', '30'));
  });

  testWidgets('the letters under the box follow a backspace and a fix in the middle', (t) async {
    await t.pumpWidget(host(PriceFields(cost: '', selling: '', code: example)));
    for (final step in ['E', '2S', '23X']) {
      await t.enterText(box('Cost price'), step);
      await t.pumpAndSettle();
    }
    expect((text(t, 'Cost price'), find.text('ESX').evaluate().length), ('230', 1));
    await t.enterText(box('Cost price'), '23'); // backspace
    await t.pumpAndSettle();
    expect(find.text('ES'), findsOneWidget);
    await t.enterText(box('Cost price'), '2R3'); // 'r' typed in the middle
    await t.pumpAndSettle();
    expect((text(t, 'Cost price'), find.text('ERS').evaluate().length), ('213', 1));
    await t.pump(const Duration(seconds: 1));
  });
}
