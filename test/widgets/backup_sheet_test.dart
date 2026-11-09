import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/data/db.dart';
import 'package:karots_suite_onboard/main.dart';
import 'package:karots_suite_onboard/screens/backup_sheet.dart';
import 'package:karots_suite_onboard/settings/secure.dart';
import 'package:karots_suite_onboard/state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  testWidgets('on a small phone the backup sheet scrolls down to Wipe', (t) async {
    await t.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final db = (await t.runAsync(() => Db.openWith(path: '${Directory.systemTemp.createTempSync('bk').path}/t.db', factory: databaseFactoryFfi)))!;
    await t.pumpWidget(
      buildApp(
        app: AppState(db, MemoryStore()),
        fonts: false,
        home: Scaffold(
          body: Builder(builder: (c) => TextButton(onPressed: () => showBackup(c), child: const Text('open'))),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull, reason: 'no overflow');
    await t.scrollUntilVisible(find.text('Wipe…'), 100, scrollable: find.byType(Scrollable).last);
    expect(find.text('Wipe…').hitTestable(), findsOneWidget);
  });
}
