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
  Widget build(BuildContext context) => buildApp(
    app: open ? app : null,
    home: open && app != null ? const AppHome() : LockScreen(store: store, onOpen: unlock),
  );
}

/// The app's frame. The shared state sits above the navigator, so every page
/// opened on top reaches it too (not only the first screen).
Widget buildApp({required AppState? app, required Widget home, ThemeMode mode = ThemeMode.system, bool fonts = true}) => MaterialApp(
  title: 'Karots Suite Onboard',
  debugShowCheckedModeBanner: false,
  theme: ksTheme(Brightness.light, fonts: fonts),
  darkTheme: ksTheme(Brightness.dark, fonts: fonts),
  themeMode: mode,
  builder: (context, child) => app == null ? child! : AppScope(state: app, child: child!),
  home: home,
);
