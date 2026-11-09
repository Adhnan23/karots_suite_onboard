import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/data/backup.dart';
import 'package:karots_suite_onboard/data/db.dart';
import 'package:karots_suite_onboard/data/models.dart';
import 'package:karots_suite_onboard/flavor.dart';
import 'package:karots_suite_onboard/input/cost_code.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'cost_code_test.dart' show example;

Future<Db> fresh() => Db.openWith(path: inMemoryDatabasePath, factory: databaseFactoryFfi);

void main() {
  sqfliteFfiInit();
  final pulled = DateTime(2026, 11, 8, 10);

  test('a shop keeps its code and the backup carries it', () async {
    final a = await fresh();
    final s = Shop(name: 'Big Pharmacy', lastPull: pulled)
      ..costCodeJson = example.toJson()
      ..costCodeAt = DateTime(2026, 11, 9);
    await a.saveShop(s);
    final back = (await a.shops()).single;
    expect(back.costCode.decode('ESX').value, '230');
    expect(back.costCodeAt, DateTime(2026, 11, 9));
    expect(await exportBackup(a), contains('cost_code'));
    await a.close();
  });

  /// A's backup of [shopA], imported into a fresh B that holds [shopB] first
  /// (one in-memory database at a time, as in backup_test).
  Future<Shop> sync(Shop shopA, Shop shopB) async {
    final a = await fresh();
    await a.saveShop(shopA);
    final file = await exportBackup(a);
    await a.close();
    final b = await fresh();
    await b.saveShop(shopB);
    await importBackup(b, file);
    final got = (await b.shops()).single;
    await b.close();
    return got;
  }

  test('a code set on one device reaches another that pulled the shop at the same time', () async {
    final s = Shop(name: 'Big Pharmacy', lastPull: pulled);
    final there = Shop.fromRow(s.toRow());
    s
      ..costCodeJson = example.toJson()
      ..costCodeAt = DateTime(2026, 11, 9);
    expect((await sync(s, there)).costCode.decode('ESX').value, '230');
  });

  test('an older code never overwrites a newer one', () async {
    final s = Shop(name: 'Big Pharmacy', lastPull: pulled)
      ..costCodeJson = CostCode({0: 'q'}).toJson()
      ..costCodeAt = DateTime(2026, 11, 1);
    final there = Shop.fromRow(s.toRow())
      ..costCodeJson = example.toJson()
      ..costCodeAt = DateTime(2026, 11, 9);
    expect((await sync(s, there)).costCode.decode('ESX').value, '230');
  });

  test('a newer pull from another device keeps our newer code', () async {
    final s = Shop(name: 'Big Pharmacy', lastPull: DateTime(2026, 11, 9, 12));
    final there = Shop.fromRow(s.toRow())
      ..lastPull = pulled
      ..costCodeJson = example.toJson()
      ..costCodeAt = DateTime(2026, 11, 9);
    final got = await sync(s, there);
    expect(got.lastPull, DateTime(2026, 11, 9, 12));
    expect(got.costCode.decode('ESX').value, '230');
  });

  test('saving a stale shop (a connected device\'s pull) keeps the newer code already stored', () async {
    final db = await fresh();
    final live = Shop(name: 'Big Pharmacy', lastPull: pulled);
    await db.saveShop(live);
    await db.saveShop(
      Shop.fromRow(live.toRow())
        ..costCodeJson = example.toJson()
        ..costCodeAt = DateTime(2026, 11, 9),
    ); // a team sync brought the code
    live.lastPull = DateTime(2026, 11, 9, 12);
    await db.saveShop(live); // the auto pull saves its own copy
    expect((await db.shops()).single.costCode.decode('ESX').value, '230');
    expect(live.costCode.decode('ESX').value, '230', reason: 'the live copy learns it too');
    await db.close();
  });

  test('codeFor: the shop\'s code in Onboard, nothing in Shelf or when empty', () {
    final s = Shop(name: 'A')..costCodeJson = example.toJson();
    expect(codeFor(s)?.decode('ESX').value, '230');
    expect(codeFor(Shop(name: 'B')), isNull);
    setShelf(true);
    addTearDown(() => setShelf(false));
    expect(codeFor(s), isNull);
  });
}
