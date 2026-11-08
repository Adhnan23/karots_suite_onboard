import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../main.dart' show buildApp;
import '../screens/shop_screen.dart';
import '../settings/secure.dart';
import '../state.dart';
import '../suite/client.dart';
import '../theme/mode.dart';
import 'account.dart';
import 'connect_screen.dart';
import 'lock_screen.dart';

/// What the shop's page says when signing in at unlock was refused; '' when the
/// shop just isn't in reach (then work waits in the queue, nothing to say).
String connectProblem(Object e) {
  if (e is! SuiteError) return '';
  if (e.status == 401) return "Your PIN was changed on the shop's PC: lock, then sign in again with the new one";
  return e.message;
}

/// Karots Shelf's frame: sign in → lock → the shop's page. Locks after
/// [idleLock] with no touches; the PIN is held only while unlocked.
class ShelfApp extends StatefulWidget {
  const ShelfApp({super.key});
  static const idleLock = Duration(minutes: 10);
  @override
  State<ShelfApp> createState() => _ShelfAppState();
}

class _ShelfAppState extends State<ShelfApp> {
  late final KeyStore store = FallbackStore(
    SecureStore(),
    FileStore('${Platform.environment['HOME'] ?? '.'}/.local/share/karots_suite_shelf/store.json'),
  );
  late final mode = ModeController(store)..load();
  late final accounts = ShelfAccounts(store);
  AppState? app;
  ShelfAccount? who;
  Shop? shop;
  bool ready = false, open = false, signIn = false;
  String? signInPhone, device;
  Timer? idle;

  @override
  void initState() {
    super.initState();
    () async {
      var d = await store.read('shelf_device') ?? '';
      if (d.isEmpty) {
        d = newUid();
        await store.write('shelf_device', d);
      }
      device = d;
      who = await accounts.current();
      setState(() => ready = true);
    }();
  }

  Future<AppState> _app() async {
    final a = app ??= AppState(await Db.open(), store, mode);
    a
      ..shelfDevice = device!
      ..lockNow = lock;
    return a;
  }

  /// The one shop, by its address (made the first time).
  Future<Shop> _shop(AppState a, String address, {String name = ''}) async {
    final s = (await a.db.shops()).where((x) => x.address == address).firstOrNull ?? Shop(name: name.isEmpty ? 'The shop' : name, address: address);
    if (name.isNotEmpty) s.name = name;
    await a.db.saveShop(s);
    return s;
  }

  Future<void> _signedIn(SuiteClient c, ShelfUser u, String phone, String pin, String shopName) async {
    final a = await ShelfAccount.make(address: c.base, phone: phone, name: u.name, role: u.role, pin: pin);
    await accounts.save(a);
    await accounts.setCurrent(phone);
    who = a;
    shop = await _shop(await _app(), c.base, name: shopName);
    signIn = false;
    await _unlock(pin);
  }

  Future<void> _unlock(String pin) async {
    final a = await _app();
    a
      ..person = who
      ..personPin = pin;
    shop ??= await _shop(a, who!.address);
    _touch();
    setState(() => open = true);
    try {
      await a.connectPerson(shop!);
      a.connectProblem = '';
    } catch (e) {
      // Offline: work goes in the queue. Refused: the shop's page says why.
      a.connectProblem = connectProblem(e);
    }
    a.changed();
  }

  void lock() {
    idle?.cancel();
    final a = app;
    if (a != null) {
      a.personPin = null;
      if (shop != null) a.disconnect(shop!);
    }
    setState(() => open = false);
  }

  void _touch() {
    idle?.cancel();
    if (open || app?.personPin != null) idle = Timer(ShelfApp.idleLock, lock);
  }

  @override
  void dispose() {
    idle?.cancel();
    super.dispose();
  }

  Widget _home() {
    if (!ready) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (signIn || who == null) {
      return ShelfConnectScreen(
        device: device!,
        address: who?.address ?? '',
        phone: signInPhone ?? '',
        onBack: who == null ? null : () => setState(() => signIn = false),
        onSignedIn: _signedIn,
      );
    }
    if (!open || shop == null) {
      return ShelfLockScreen(
        key: ValueKey(who!.phone),
        account: who!,
        accounts: accounts,
        onOpen: _unlock,
        onSignIn: ({phone}) => setState(() {
          signIn = true;
          signInPhone = phone;
        }),
      );
    }
    return ShopScreen(shop: shop!);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _touch(),
    child: ValueListenableBuilder(
      valueListenable: mode,
      builder: (context, m, _) => buildApp(app: open ? app : null, mode: m, home: _home(), title: 'Karots Shelf'),
    ),
  );
}
