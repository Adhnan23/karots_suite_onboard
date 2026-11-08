// Karots Shelf's screens as pictures, phone, light and dark:
//   SHOTS=/some/dir flutter test test/shelf_shots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/data/db.dart';
import 'package:karots_suite_onboard/data/models.dart';
import 'package:karots_suite_onboard/flavor.dart';
import 'package:karots_suite_onboard/main.dart';
import 'package:karots_suite_onboard/screens/shop_actions.dart';
import 'package:karots_suite_onboard/screens/shop_screen.dart';
import 'package:karots_suite_onboard/settings/secure.dart';
import 'package:karots_suite_onboard/shelf/account.dart';
import 'package:karots_suite_onboard/shelf/connect_screen.dart';
import 'package:karots_suite_onboard/shelf/lock_screen.dart';
import 'package:karots_suite_onboard/state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'shots_test.dart' show font;

void main() {
  final dir = Platform.environment['SHOTS'];
  testWidgets('shelf shots', (t) async {
    await t.runAsync(() async {
      await font('Roboto', ['/usr/share/fonts/noto/NotoSans-Regular.ttf', '/usr/share/fonts/noto/NotoSans-Bold.ttf']);
      await font('MaterialIcons', ['/opt/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
    });
    setShelf(true);
    registerShopActions();
    sqfliteFfiInit();
    final db = (await t.runAsync(() => Db.openWith(path: inMemoryDatabasePath, factory: databaseFactoryFfi)))!;
    final shop = Shop(
      name: 'Iman Pharmacy',
      address: 'http://192.168.1.10:3000',
      lastPull: DateTime(2026, 11, 8, 9, 30),
      snapshot: {'stockTake': true},
    );
    final who = (await t.runAsync(
      () => ShelfAccount.make(address: shop.address, phone: '0771111111', name: 'Nimali', role: 'cashier', pin: '1234'),
    ))!;
    final app = AppState(db, MemoryStore())..person = who;
    final accounts = ShelfAccounts(MemoryStore());
    final screens = <String, Widget>{
      'shelf-connect': ShelfConnectScreen(device: 'd', onSignedIn: (_, _, _, _, _) {}),
      'shelf-lock': ShelfLockScreen(account: who, accounts: accounts, onOpen: (_) {}, onSignIn: ({phone}) {}),
      'shelf-shop': ShopScreen(shop: shop),
    };
    const size = Size(390, 844);
    for (final b in Brightness.values) {
      for (final e in screens.entries) {
        await t.binding.setSurfaceSize(size);
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        final key = GlobalKey();
        await t.pumpWidget(
          RepaintBoundary(
            key: key,
            child: buildApp(app: app, home: e.value, fonts: false, mode: b == Brightness.dark ? ThemeMode.dark : ThemeMode.light),
          ),
        );
        await t.runAsync(() => Future.delayed(const Duration(milliseconds: 250)));
        await t.pump();
        final img = await t.runAsync(() async {
          final i = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 1.5);
          return (await i.toByteData(format: ui.ImageByteFormat.png))!;
        });
        File('$dir/${e.key}-${b.name}.png').writeAsBytesSync(img!.buffer.asUint8List());
      }
    }
    setShelf(false);
    await t.runAsync(() => db.close());
  }, skip: dir == null);
}
