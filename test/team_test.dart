import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/data/db.dart';
import 'package:karots_suite_onboard/data/models.dart';
import 'package:karots_suite_onboard/sync/team.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Db> fresh() => Db.openWith(path: '${Directory.systemTemp.createTempSync('ob').path}/db', factory: databaseFactoryFfi);

void main() {
  sqfliteFfiInit();

  test('a team key looks like KT-XXXX-XXXX-XXXX and its fingerprint never shows it', () {
    final k = newTeamKey();
    expect(RegExp(r'^KT-[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$').hasMatch(k), isTrue);
    expect(teamPrint(k), isNot(contains(k.substring(3, 7))));
    expect(teamPrint(k), teamPrint(' ${k.toLowerCase()} '), reason: 'typed in any case');
  });

  test('announcements: ours are read back; another team or our own device is ignored', () {
    final msg = announce('dev-a', teamPrint('KT-AAAA-BBBB-CCCC'), 8765);
    expect(readAnnounce(msg, myDevice: 'dev-b', myPrint: teamPrint('KT-AAAA-BBBB-CCCC')), (device: 'dev-a', port: 8765));
    expect(readAnnounce(msg, myDevice: 'dev-a', myPrint: teamPrint('KT-AAAA-BBBB-CCCC')), isNull);
    expect(readAnnounce(msg, myDevice: 'dev-b', myPrint: teamPrint('KT-ZZZZ-BBBB-CCCC')), isNull);
    expect(readAnnounce('hello', myDevice: 'dev-b', myPrint: 'x'), isNull);
  });

  test('two team devices keep each other the same; a device with another key is refused', () async {
    const key = 'KT-AAAA-BBBB-CCCC';
    final pc = await fresh(), phone = await fresh(), stranger = await fresh();
    final a = TeamSync(pc, key: key, device: 'pc', port: 0, discover: false);
    final b = TeamSync(phone, key: key, device: 'phone', port: 0, discover: false);
    final x = TeamSync(stranger, key: 'KT-ZZZZ-ZZZZ-ZZZZ', device: 'x', port: 0, discover: false);
    await a.start();
    await b.start();
    await x.start();
    await pc.saveProduct(CatalogProduct(name: 'From the PC', barcode: '1'));
    await phone.saveShop(Shop(name: 'Iman'));
    b.addPeer('phone-sees-pc', '127.0.0.1', a.port);
    await b.syncNow();
    expect([for (final p in await phone.products()) p.name], ['From the PC']);
    expect([for (final s in await pc.shops()) s.name], ['Iman']);
    expect(b.peers.single.error, isEmpty);
    x.addPeer('x-sees-pc', '127.0.0.1', a.port);
    await x.syncNow();
    expect(x.peers.single.error, contains('another team'));
    expect(await stranger.products(), isEmpty);
    for (final t in [a, b, x]) {
      await t.stop();
    }
  });

  test('after leaving, a change here starts no sync', () async {
    final pc = await fresh(), phone = await fresh();
    final a = TeamSync(pc, key: 'KT-AAAA-BBBB-CCCC', device: 'pc', port: 0, discover: false);
    final b = TeamSync(phone, key: 'KT-AAAA-BBBB-CCCC', device: 'phone', port: 0, discover: false);
    await a.start();
    await b.start();
    b.addPeer('pc', '127.0.0.1', a.port);
    await b.syncNow();
    await b.stop();
    await phone.saveProduct(CatalogProduct(name: 'After leaving'));
    b.soon();
    await b.syncNow();
    expect(await pc.products(), isEmpty);
    await a.stop();
  });
}
