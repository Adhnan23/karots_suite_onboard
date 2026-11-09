import 'dart:io';

import 'package:convert/convert.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/data/db.dart';
import 'package:karots_suite_onboard/data/models.dart';
import 'package:karots_suite_onboard/lock/app_identity.dart';
import 'package:karots_suite_onboard/main.dart';
import 'package:karots_suite_onboard/screens/wipe_sheet.dart';
import 'package:karots_suite_onboard/settings/secrets.dart';
import 'package:karots_suite_onboard/settings/secure.dart';
import 'package:karots_suite_onboard/state.dart';
import 'package:karots_suite_onboard/suite/support_pin.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  final code = pinFromSeed(hex.decode(appSeedHex), DateTime.now());

  Future<(AppState, List<String>)> open(WidgetTester t, {bool saved = true}) async {
    final db = (await t.runAsync(() => Db.openWith(path: '${Directory.systemTemp.createTempSync('wipe').path}/t.db', factory: databaseFactoryFfi)))!;
    await t.runAsync(() async {
      await db.saveProduct(CatalogProduct(name: 'Panadol'));
      await db.saveSupplier(CatalogSupplier(name: 'Hemas'));
      await db.saveShop(Shop(name: 'Iman'));
    });
    final app = AppState(db, MemoryStore());
    await t.runAsync(() => Secrets(app.store).save([(name: 'Main', secret: 'abc')]));
    final backups = <String>[];
    await t.pumpWidget(
      buildApp(
        app: app,
        fonts: false,
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () => showWipe(
                c,
                save: (text, name) async {
                  backups.add(text);
                  return saved;
                },
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
    await t.pumpAndSettle();
    return (app, backups);
  }

  Future<void> enterCode(WidgetTester t, String c) async {
    await t.enterText(find.widgetWithText(TextField, 'Code'), c);
    await t.tap(find.widgetWithText(FilledButton, 'Wipe'));
    for (var i = 0; i < 8; i++) {
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 100))); // real database work
      await t.pump();
    }
    await t.pumpAndSettle();
  }

  testWidgets('only what is ticked goes, after this hour\'s code and a saved backup', (t) async {
    final (app, backups) = await open(t);
    await t.tap(find.textContaining('Catalogue products'));
    await t.pumpAndSettle();
    await t.tap(find.text('Back up and wipe'));
    await t.pumpAndSettle();
    await enterCode(t, '000000');
    expect(find.text('That isn\'t this hour\'s code'), findsOneWidget);
    expect(backups, isEmpty);
    await enterCode(t, code);
    expect(backups.single, contains('Panadol'), reason: 'the backup is made before the wipe');
    await t.runAsync(() async {
      expect(await app.db.products(), isEmpty);
      expect(await app.db.suppliers(), isNotEmpty);
      expect(await app.db.shops(), isNotEmpty);
      expect(await Secrets(app.store).all(), isNotEmpty);
    });
  });

  testWidgets('Wipe all takes everything, secrets too', (t) async {
    final (app, _) = await open(t);
    await t.tap(find.text('Wipe all'));
    await t.pumpAndSettle();
    await enterCode(t, code);
    await t.runAsync(() async {
      final n = await app.db.counts();
      expect((n.products, n.suppliers, n.shops, n.review), (0, 0, 0, 0));
      expect(await Secrets(app.store).all(), isEmpty);
    });
  });

  testWidgets('a backup that wasn\'t saved stops the wipe', (t) async {
    final (app, backups) = await open(t, saved: false);
    await t.tap(find.text('Wipe all'));
    await t.pumpAndSettle();
    await enterCode(t, code);
    expect(backups, hasLength(1));
    await t.runAsync(() async => expect((await app.db.counts()).products, 1));
  });
}
