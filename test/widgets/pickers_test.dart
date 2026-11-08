import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/input/category_field.dart';
import 'package:karots_suite_onboard/input/supplier_field.dart';
import 'package:karots_suite_onboard/theme/app_theme.dart';

Widget host(Widget child) => MaterialApp(
  theme: ksTheme(Brightness.light, fonts: false),
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
);

void main() {
  testWidgets('category: open a branch, add a sub-category, it is picked', (t) async {
    final ctl = TextEditingController();
    await t.pumpWidget(host(CategoryField(controller: ctl, paths: const ['Medicine > Pain', 'Cleaning'])));
    expect(find.text('Uncategorized: the shop files it'), findsOneWidget);
    await t.tap(find.byType(CategoryField));
    await t.pumpAndSettle();
    expect(find.text('Pain'), findsNothing, reason: 'branches start closed');
    await t.tap(find.byTooltip('Open'));
    await t.pumpAndSettle();
    expect(find.text('Pain'), findsOneWidget);
    await t.tap(find.byTooltip('Add under Pain'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Name'), 'Fever');
    await t.tap(find.widgetWithText(FilledButton, 'Add'));
    await t.pumpAndSettle();
    expect(ctl.text, 'Medicine > Pain > Fever');
  });

  testWidgets('category: search finds a deep one', (t) async {
    final ctl = TextEditingController();
    await t.pumpWidget(host(CategoryField(controller: ctl, paths: const ['Medicine > Pain > Children', 'Cleaning'])));
    await t.tap(find.byType(CategoryField));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Search categories'), 'child');
    await t.pumpAndSettle();
    await t.tap(find.text('Children'));
    await t.pumpAndSettle();
    expect(ctl.text, 'Medicine > Pain > Children');
  });

  testWidgets('supplier: search the shop\'s and the catalogue\'s, or add a new one', (t) async {
    String choice = 'none';
    await t.pumpWidget(
      host(
        StatefulBuilder(
          builder: (c, set) => SupplierField(
            value: choice,
            shop: const [(id: 3, name: 'Hemas Pharma'), (id: 4, name: 'State Pharmaceuticals')],
            catalogue: const [(uid: 'u1', name: 'Lanka Wire')],
            onChanged: (v) => set(() => choice = v),
          ),
        ),
      ),
    );
    expect(find.text('None'), findsOneWidget);
    await t.tap(find.byType(SupplierField));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Search suppliers'), 'hem');
    await t.pumpAndSettle();
    expect(find.text('State Pharmaceuticals'), findsNothing);
    await t.tap(find.text('Hemas Pharma'));
    await t.pumpAndSettle();
    expect(choice, 'shop:3');
    expect(find.text('Hemas Pharma'), findsOneWidget);

    await t.tap(find.byType(SupplierField));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Search suppliers'), 'New Traders');
    await t.pumpAndSettle();
    await t.tap(find.textContaining('Add “New Traders”'));
    await t.pumpAndSettle();
    expect(choice, 'new:New Traders');
  });
}
