import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/data/db.dart';
import 'package:karots_suite_onboard/data/drafts.dart';
import 'package:karots_suite_onboard/data/models.dart';
import 'package:karots_suite_onboard/main.dart';
import 'package:karots_suite_onboard/screens/catalog_screen.dart';
import 'package:karots_suite_onboard/settings/secure.dart';
import 'package:karots_suite_onboard/state.dart';
import 'package:karots_suite_onboard/sync/push.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('a shop\'s new product starts with its default unit, else pcs', () {
    final s = Shop(
      name: 'A',
      snapshot: {
        'units': [
          {'id': 1, 'abbreviation': 'pcs', 'isDefault': false},
          {'id': 2, 'abbreviation': 'tab', 'isDefault': true},
        ],
      },
    );
    expect(newShopProduct(s).unit, 'tab');
    expect(
      newShopProduct(
        Shop(
          name: 'old pull',
          snapshot: {
            'units': [
              {'id': 1, 'abbreviation': 'kg'},
            ],
          },
        ),
      ).unit,
      'pcs',
    );
  });

  testWidgets('going back from New product keeps it; Start over clears it; an edit asks before losing changes', (t) async {
    sqfliteFfiInit();
    final db = (await t.runAsync(() => Db.openWith(path: inMemoryDatabasePath, factory: databaseFactoryFfi)))!;
    final app = AppState(db, MemoryStore());
    catalogNewDraft = null;
    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await t.pump(const Duration(milliseconds: 400));
      }
    }

    await t.pumpWidget(buildApp(app: app, home: const CatalogScreen()));
    await settle();
    await t.tap(find.text('New product'));
    await settle();
    await t.enterText(find.widgetWithText(TextField, 'Name'), 'Samaposha 200g');
    await t.pageBack();
    await settle();
    expect(find.text('Samaposha 200g'), findsNothing); // back on the list, nothing saved
    expect(catalogNewDraft?.name, 'Samaposha 200g');

    await t.tap(find.text('New product'));
    await settle();
    expect(find.widgetWithText(TextField, 'Samaposha 200g'), findsOneWidget);
    expect(find.text('Start over'), findsOneWidget);
    await t.tap(find.text('Start over'));
    await settle();
    expect(catalogNewDraft, isNull);
    expect(find.widgetWithText(TextField, 'Samaposha 200g'), findsNothing);

    await t.enterText(find.widgetWithText(TextField, 'Name'), 'Saved one');
    await t.tap(find.text('Save'));
    await settle();
    expect(catalogNewDraft, isNull);
    await settle();
    expect(find.text('Saved one'), findsOneWidget);

    await t.tap(find.text('Saved one'));
    await settle();
    await t.enterText(find.widgetWithText(TextField, 'Name'), 'Saved one, renamed');
    await t.pageBack();
    await settle();
    expect(find.text('Leave without saving?'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await settle();
    expect(find.widgetWithText(TextField, 'Saved one, renamed'), findsOneWidget);
    await t.runAsync(() => db.close());
  });
}
