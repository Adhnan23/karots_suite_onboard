import 'package:flutter/material.dart';

/// Karots Suite's Studio palette (web/src/theme/palettes/dock/studio.css), both modes.
class KsColors {
  const KsColors({
    required this.background,
    required this.card,
    required this.foreground,
    required this.muted,
    required this.mutedForeground,
    required this.faint,
    required this.border,
    required this.brand,
    required this.brandForeground,
    required this.brandSoft,
    required this.selected,
    required this.selectedForeground,
    required this.success,
    required this.danger,
    required this.warning,
  });
  final Color background, card, foreground, muted, mutedForeground, faint, border;
  final Color brand, brandForeground, brandSoft, selected, selectedForeground;
  final Color success, danger, warning;
}

class KsTokens {
  static const double radius = 16;
  static const double radiusSm = 11;

  static const light = KsColors(
    background: Color(0xFFEFF0F3),
    card: Color(0xFFFFFFFF),
    foreground: Color(0xFF15161A),
    muted: Color(0xFFF6F7F9),
    mutedForeground: Color(0xFF5A5E69),
    faint: Color(0xFF6E727D),
    border: Color(0xFFE4E6EB),
    brand: Color(0xFFF2A900),
    brandForeground: Color(0xFF15161A),
    brandSoft: Color(0xFFFFF4D6),
    selected: Color(0xFF15161A),
    selectedForeground: Color(0xFFFFFFFF),
    success: Color(0xFF12955A),
    danger: Color(0xFFD23F3F),
    warning: Color(0xFFB66A00),
  );

  static const dark = KsColors(
    background: Color(0xFF111215),
    card: Color(0xFF1B1C21),
    foreground: Color(0xFFEDEEF1),
    muted: Color(0xFF24262C),
    mutedForeground: Color(0xFFA6A9B3),
    faint: Color(0xFF8A8E99),
    border: Color(0xFF2E3038),
    brand: Color(0xFFF5B820),
    brandForeground: Color(0xFF15161A),
    brandSoft: Color(0x29F5B820),
    selected: Color(0xFFEDEEF1),
    selectedForeground: Color(0xFF111215),
    success: Color(0xFF3CCB84),
    danger: Color(0xFFF27272),
    warning: Color(0xFFF0A23B),
  );

  static KsColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}
