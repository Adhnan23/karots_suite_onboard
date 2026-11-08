import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/data/db.dart';
import 'package:karots_suite_onboard/main.dart';
import 'package:karots_suite_onboard/settings/secure.dart';
import 'package:karots_suite_onboard/state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  testWidgets('a page opened on top still reaches the app (the real app\'s wiring)', (t) async {
    sqfliteFfiInit();
    final db = (await t.runAsync(() => Db.openWith(path: inMemoryDatabasePath, factory: databaseFactoryFfi)))!;
    final app = AppState(db, MemoryStore());
    late BuildContext home;
    await t.pumpWidget(
      buildApp(
        app: app,
        home: Builder(
          builder: (c) {
            home = c;
            return const Text('home');
          },
        ),
      ),
    );
    Navigator.push(home, MaterialPageRoute(builder: (c) => Text('pushed ${identical(AppScope.of(c), app)}')));
    await t.pumpAndSettle();
    expect(find.text('pushed true'), findsOneWidget);
    await t.runAsync(() => db.close());
  });
}
