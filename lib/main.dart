import 'dart:io';

import 'package:flutter/material.dart';

import 'app.dart';
import 'data/db.dart';
import 'data/drafts.dart';
import 'state.dart';
import 'lock/lock_screen.dart';
import 'screens/shop_actions.dart';
import 'settings/secure.dart';
import 'theme/app_theme.dart';
import 'theme/mode.dart';

void main() {
  registerShopActions();
  runApp(const OnboardApp());
}

class OnboardApp extends StatefulWidget {
  const OnboardApp({super.key});
  @override
  State<OnboardApp> createState() => _OnboardAppState();
}

class _OnboardAppState extends State<OnboardApp> {
  late final KeyStore store = FallbackStore(SecureStore(), FileStore('${Platform.environment['HOME'] ?? '.'}/.local/share/karots_suite_onboard/store.json'));
  late final mode = ModeController(store)..load();
  bool open = false;
  AppState? app;

  Future<void> unlock() async {
    if (app == null) {
      app = AppState(await Db.open(), store, mode);
      await loadDrafts(app!.db);
      app!.db.products().ignore(); // warm the catalogue while the home screen shows
    }
    await app!.resumeTeam();
    setState(() => open = true);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: mode,
    builder: (context, m, _) => buildApp(
      app: open ? app : null,
      mode: m,
      home: open && app != null ? const AppHome() : LockScreen(store: store, onOpen: unlock),
    ),
  );
}

/// The app's frame. The shared state sits above the navigator, so every page
/// opened on top reaches it too (not only the first screen).
Widget buildApp({required AppState? app, required Widget home, ThemeMode mode = ThemeMode.system, bool fonts = true, String title = 'Karots Suite Onboard'}) =>
    MaterialApp(
      title: title,
      debugShowCheckedModeBanner: false,
      theme: ksTheme(Brightness.light, fonts: fonts),
      darkTheme: ksTheme(Brightness.dark, fonts: fonts),
      themeMode: mode,
      builder: (context, child) => app == null ? child! : AppScope(state: app, child: child!),
      home: home,
    );
