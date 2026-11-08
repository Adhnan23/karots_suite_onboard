import 'package:flutter/material.dart';

import 'app.dart';
import 'data/db.dart';
import 'state.dart';
import 'lock/lock_screen.dart';
import 'screens/shop_actions.dart';
import 'settings/secure.dart';
import 'theme/app_theme.dart';

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
  final store = SecureStore();
  bool open = false;
  AppState? app;

  Future<void> unlock() async {
    app ??= AppState(await Db.open(), store);
    setState(() => open = true);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Karots Suite Onboard',
    debugShowCheckedModeBanner: false,
    theme: ksTheme(Brightness.light),
    darkTheme: ksTheme(Brightness.dark),
    home: open && app != null ? AppScope(state: app!, child: const AppHome()) : LockScreen(store: store, onOpen: unlock),
  );
}
