/// What a field holds, so text read from a photo can be cleaned for it.
enum FieldKind { text, number, date, barcode }

/// Cleans picked OCR text for a field: numbers keep digits and one point, codes
/// keep letters and digits, dates become YYYY-MM-DD (day first, as printed in
/// Sri Lanka; a month alone means its last day), text gets single spaces.
String filterFor(FieldKind kind, String picked) {
  switch (kind) {
    case FieldKind.text:
      return picked.replaceAll(RegExp(r'\s+'), ' ').trim();
    case FieldKind.barcode:
      return picked.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    case FieldKind.number:
      final start = picked.indexOf(RegExp(r'\d'));
      if (start < 0) return '';
      final s = picked.substring(start).replaceAll(RegExp(r'[^0-9.]'), ''); // "Rs." before the digits isn't a point
      final i = s.indexOf('.');
      final out = i < 0 ? s : s.substring(0, i + 1) + s.substring(i + 1).replaceAll('.', '');
      return out.replaceAll(RegExp(r'^\.|\.$'), '');
    case FieldKind.date:
      return _date(picked);
  }
}

String _date(String s) {
  String two(int n) => n.toString().padLeft(2, '0');
  String? ymd(int y, int m, int? d) {
    if (y < 100) y += 2000;
    if (m < 1 || m > 12) return null;
    final last = DateTime.utc(y, m + 1, 0).day;
    final day = d ?? last;
    if (day < 1 || day > last) return null;
    return '$y-${two(m)}-${two(day)}';
  }

  int n(String x) => int.parse(x);
  Match? m;
  if ((m = RegExp(r'(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})').firstMatch(s)) != null) {
    return ymd(n(m!.group(1)!), n(m.group(2)!), n(m.group(3)!)) ?? '';
  }
  if ((m = RegExp(r'(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})').firstMatch(s)) != null) {
    return ymd(n(m!.group(3)!), n(m.group(2)!), n(m.group(1)!)) ?? '';
  }
  if ((m = RegExp(r'(\d{4})[-/.](\d{1,2})(?!\d)').firstMatch(s)) != null) {
    return ymd(n(m!.group(1)!), n(m.group(2)!), null) ?? '';
  }
  if ((m = RegExp(r'(\d{1,2})[-/.](\d{4}|\d{2})(?!\d)').firstMatch(s)) != null) {
    return ymd(n(m!.group(2)!), n(m.group(1)!), null) ?? '';
  }
  return '';
}
