import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/theme/app_theme.dart';
import 'package:karots_suite_onboard/theme/tokens.dart';

void main() {
  test('Studio palette, light and dark', () {
    final light = ksTheme(Brightness.light, fonts: false);
    final dark = ksTheme(Brightness.dark, fonts: false);
    expect(light.colorScheme.primary, const Color(0xFFF2A900));
    expect(dark.colorScheme.primary, const Color(0xFFF5B820));
    expect(light.scaffoldBackgroundColor, const Color(0xFFEFF0F3));
    expect(dark.scaffoldBackgroundColor, const Color(0xFF111215));
    expect((light.cardTheme.shape as RoundedRectangleBorder).borderRadius, BorderRadius.circular(KsTokens.radius));
    expect(KsTokens.radius, 16);
  });
}
