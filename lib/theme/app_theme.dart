import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

/// The app in Karots Suite's look: Studio colours, 16px corners, pills, Figtree.
ThemeData ksTheme(Brightness b, {bool fonts = true}) {
  final c = b == Brightness.dark ? KsTokens.dark : KsTokens.light;
  final scheme = ColorScheme(
    brightness: b,
    primary: c.brand,
    onPrimary: c.brandForeground,
    secondary: c.selected,
    onSecondary: c.selectedForeground,
    error: c.danger,
    onError: b == Brightness.dark ? const Color(0xFF15161A) : Colors.white,
    surface: c.card,
    onSurface: c.foreground,
    surfaceContainerHighest: c.muted,
    onSurfaceVariant: c.mutedForeground,
    outline: c.border,
    outlineVariant: c.border,
  );
  final round = RoundedRectangleBorder(borderRadius: BorderRadius.circular(KsTokens.radius));
  const pill = StadiumBorder();
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: b, fontFamily: fonts ? GoogleFonts.figtree().fontFamily : null);
  final text = base.textTheme;
  final label = (text.labelLarge ?? const TextStyle()).copyWith(fontWeight: FontWeight.w700); // keeps the app's font
  return base.copyWith(
    scaffoldBackgroundColor: c.background,
    textTheme: text.apply(bodyColor: c.foreground, displayColor: c.foreground),
    cardTheme: CardThemeData(
      color: c.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: round.copyWith(side: BorderSide(color: c.border)),
    ),
    appBarTheme: AppBarTheme(backgroundColor: c.background, foregroundColor: c.foreground, elevation: 0, scrolledUnderElevation: 0, centerTitle: false),
    dividerTheme: DividerThemeData(color: c.border, space: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.brand,
        foregroundColor: c.brandForeground,
        shape: pill,
        minimumSize: const Size(0, 44),
        textStyle: label,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.foreground,
        side: BorderSide(color: c.border),
        shape: pill,
        minimumSize: const Size(0, 44),
        textStyle: label,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: c.foreground, shape: pill, textStyle: label),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.selected,
      foregroundColor: c.selectedForeground,
      shape: pill,
      elevation: 2,
      highlightElevation: 4,
      extendedTextStyle: label,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: c.brandSoft,
        selectedForegroundColor: c.foreground,
        foregroundColor: c.foreground,
        side: BorderSide(color: c.border),
        textStyle: label.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.card,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KsTokens.radiusSm),
        borderSide: BorderSide(color: c.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KsTokens.radiusSm),
        borderSide: BorderSide(color: c.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KsTokens.radiusSm),
        borderSide: BorderSide(color: c.brand, width: 2),
      ),
      labelStyle: TextStyle(color: c.mutedForeground),
    ),
    chipTheme: ChipThemeData(
      shape: pill,
      side: BorderSide(color: c.border),
      backgroundColor: c.muted,
      selectedColor: c.brandSoft,
      labelStyle: TextStyle(color: c.foreground, fontWeight: FontWeight.w600),
      secondaryLabelStyle: TextStyle(color: c.foreground, fontWeight: FontWeight.w600),
      checkmarkColor: c.foreground,
    ),
    navigationBarTheme: NavigationBarThemeData(backgroundColor: c.card, indicatorColor: c.brandSoft),
    navigationRailTheme: NavigationRailThemeData(backgroundColor: c.card, indicatorColor: c.brandSoft),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(KsTokens.radius))),
    ),
    dialogTheme: DialogThemeData(backgroundColor: c.card, shape: round),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.selected,
      contentTextStyle: TextStyle(color: c.selectedForeground),
      shape: round,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.brand : null),
      checkColor: WidgetStatePropertyAll(c.brandForeground),
    ),
  );
}
