import 'dart:convert';

import '../data/models.dart';
import '../flavor.dart';

/// A shop's secret cost letters (Onboard only): each digit has one or more
/// letters, so "ESX" written on a box reads 230. Matched ignoring case; a typed
/// point passes through.
class CostCode {
  CostCode(Map<int, String> letters)
    : letters = {
        for (final e in letters.entries)
          if (e.value.trim().isNotEmpty) e.key: e.value.replaceAll(RegExp(r'\s'), '').toLowerCase(),
      };

  /// Digit → its letters, lower case ({0: 'ix', 1: 'r', …}).
  final Map<int, String> letters;

  factory CostCode.fromJson(String s) {
    try {
      final m = jsonDecode(s) as Map;
      return CostCode({for (final e in m.entries) int.parse('${e.key}'): '${e.value}'});
    } catch (_) {
      return CostCode({}); // a broken copy (sync, an old backup) reads as no code, never a crash
    }
  }

  String toJson() => jsonEncode({for (final e in letters.entries) '${e.key}': e.value});

  bool get isEmpty => letters.isEmpty;

  /// "'x' is on both 0 and 3" when a letter means two digits, else null.
  String? problem() {
    final seen = <String, int>{};
    for (final d in (letters.keys.toList()..sort())) {
      for (final ch in letters[d]!.split('')) {
        if (RegExp(r'[0-9.]').hasMatch(ch)) return "$d has '$ch': use letters only";
        final was = seen[ch];
        if (was != null && was != d) return "'$ch' is on both $was and $d";
        seen[ch] = d;
      }
    }
    return null;
  }

  /// Any letter, in any script (Sinhala, Tamil…): whatever isn't a digit, point, comma or space.
  bool hasLetters(String typed) => RegExp(r'[^0-9.,\s]').hasMatch(typed);

  /// The digits for what was typed; an unknown letter is an error naming it.
  ({String value, String? error}) decode(String typed) {
    final digit = {
      for (final e in letters.entries)
        for (final ch in e.value.split('')) ch: e.key,
    };
    final out = StringBuffer();
    for (final ch in typed.replaceAll(RegExp(r'[,\s]'), '').toLowerCase().runes.map(String.fromCharCode)) {
      if (ch.isEmpty) continue;
      if (RegExp(r'[0-9.]').hasMatch(ch)) {
        out.write(ch);
      } else if (digit.containsKey(ch)) {
        out.write(digit[ch]);
      } else {
        return (value: '', error: "'$ch' isn't in this shop's code");
      }
    }
    return (value: out.toString(), error: null);
  }
}

/// The shop's code for typing costs: Onboard only (Shelf's staff know their own
/// code), null when the shop has none.
CostCode? codeFor(Shop shop) {
  if (isShelf) return null;
  final c = shop.costCode;
  return c.isEmpty ? null : c;
}
