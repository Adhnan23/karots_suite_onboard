import 'package:flutter/material.dart';

import 'theme/app_theme.dart';

/// Karots Suite Shelf: `flutter build apk --flavor shelf -t lib/main_shelf.dart`.
void main() => runApp(
  MaterialApp(
    title: 'Karots Shelf',
    debugShowCheckedModeBanner: false,
    theme: ksTheme(Brightness.light),
    home: const Scaffold(body: Center(child: Text('Karots Shelf'))),
  ),
);
