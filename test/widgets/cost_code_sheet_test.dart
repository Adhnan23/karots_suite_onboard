import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/input/cost_code.dart';
import 'package:karots_suite_onboard/screens/cost_code_sheet.dart';
import 'package:karots_suite_onboard/theme/app_theme.dart';

Widget opener(CostCode current, void Function(CostCode?) got) => MaterialApp(
  theme: ksTheme(Brightness.light, fonts: false),
  home: Scaffold(
    body: Builder(
      builder: (c) => TextButton(onPressed: () async => got(await editCostCode(c, current)), child: const Text('open')),
    ),
  ),
);

Finder digit(int d) => find.widgetWithText(TextField, '$d');

void main() {
  testWidgets('the cheat sheet typed in decodes; several letters on a digit are fine', (t) async {
    CostCode? got;
    await t.pumpWidget(opener(CostCode({}), (v) => got = v));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    const sheet = {0: 'ix', 1: 'r', 2: 'e', 3: 's', 4: 'u', 5: 'l', 6: 'o', 7: 'n', 8: 'a', 9: 'b'};
    for (final e in sheet.entries) {
      await t.enterText(digit(e.key), e.value);
    }
    await t.pumpAndSettle();
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(got!.decode('ESX').value, '230');
  });

  testWidgets('a letter on two digits is shown and Save is off', (t) async {
    CostCode? got;
    await t.pumpWidget(opener(CostCode({}), (v) => got = v));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.enterText(digit(0), 'ix');
    await t.enterText(digit(3), 'sx');
    await t.pumpAndSettle();
    expect(find.text("'x' is on both 0 and 3"), findsOneWidget);
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNull);
    expect(got, isNull);
  });

  testWidgets('Clear empties the code', (t) async {
    CostCode? got;
    await t.pumpWidget(opener(CostCode({1: 'r'}), (v) => got = v));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.tap(find.text('Clear'));
    await t.pumpAndSettle();
    expect(got!.isEmpty, isTrue);
  });
}
