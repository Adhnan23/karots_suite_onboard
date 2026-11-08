import 'package:flutter/material.dart';

import 'app.dart';
import 'lock/lock_screen.dart';
import 'settings/secure.dart';
import 'theme/app_theme.dart';

void main() => runApp(const OnboardApp());

class OnboardApp extends StatefulWidget {
  const OnboardApp({super.key});
  @override
  State<OnboardApp> createState() => _OnboardAppState();
}

class _OnboardAppState extends State<OnboardApp> {
  final store = SecureStore();
  bool open = false;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Karots Suite Onboard',
    debugShowCheckedModeBanner: false,
    theme: ksTheme(Brightness.light),
    darkTheme: ksTheme(Brightness.dark),
    home: open ? AppHome(store: store) : LockScreen(store: store, onOpen: () => setState(() => open = true)),
  );
}
