import 'package:flutter/material.dart';

import '../settings/secure.dart';

/// Light, dark or follow the device; kept on this device.
class ModeController extends ValueNotifier<ThemeMode> {
  ModeController(this.store) : super(ThemeMode.system);
  final KeyStore store;
  static const key = 'theme_mode';

  Future<void> load() async {
    final v = await store.read(key);
    value = ThemeMode.values.where((m) => m.name == v).firstOrNull ?? ThemeMode.system;
  }

  Future<void> next() async {
    value = switch (value) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    await store.write(key, value.name);
  }
}

/// The switch, for the page heads.
class ModeButton extends StatelessWidget {
  const ModeButton({super.key, required this.mode});
  final ModeController mode;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: mode,
    builder: (context, m, _) => IconButton(
      tooltip: switch (m) {
        ThemeMode.system => 'Follows the device · tap for light',
        ThemeMode.light => 'Light · tap for dark',
        ThemeMode.dark => 'Dark · tap to follow the device',
      },
      icon: Icon(switch (m) {
        ThemeMode.system => Icons.brightness_auto_rounded,
        ThemeMode.light => Icons.light_mode_rounded,
        ThemeMode.dark => Icons.dark_mode_rounded,
      }),
      onPressed: mode.next,
    ),
  );
}
