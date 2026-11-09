import 'cost_code.dart';

/// What's typed in the price boxes: cost (digits, or the shop's code letters),
/// selling, Markup × and ÷ how many (per; blank = no dividing).
class PriceInput {
  const PriceInput({this.cost = '', this.selling = '', this.markup = '', this.per = ''});
  final String cost, selling, markup, per;

  PriceInput copyWith({String? cost, String? selling, String? markup, String? per}) =>
      PriceInput(cost: cost ?? this.cost, selling: selling ?? this.selling, markup: markup ?? this.markup, per: per ?? this.per);
}

double _num(String s) => double.tryParse(s.trim()) ?? 0;

/// v to at most [places] decimals, trailing zeros dropped (23, 33.3333, 12.5).
String trimDec(double v, int places) {
  var s = v.toStringAsFixed(places);
  if (s.contains('.')) s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  return s;
}

/// Markup as "1.15" (selling ÷ cost), '' when there's no cost to divide by (Suite price.ts).
String markupOf(String cost, String selling) => _num(cost) > 0 && _num(selling) > 0 ? trimDec(_num(selling) / _num(cost), 2) : '';

String _costNumber(String typed, CostCode? code) => code == null ? typed : code.decode(typed).value;

/// Cost ⇄ markup ⇄ selling (Suite price.ts): cost or markup set the selling
/// price; selling sets the markup. The typed cost is never rewritten.
PriceInput editPrice(PriceInput p, String field, String value, CostCode? code) {
  final next = switch (field) {
    'cost' => p.copyWith(cost: value),
    'markup' => p.copyWith(markup: value),
    'selling' => p.copyWith(selling: value),
    _ => p.copyWith(per: value),
  };
  if (field == 'per') return next;
  final cost = _costNumber(next.cost, code);
  if (field == 'selling') return next.copyWith(markup: markupOf(cost, value));
  if (_num(cost) > 0 && _num(next.markup) > 0) return next.copyWith(selling: trimDec(_num(cost) * _num(next.markup), 2));
  return field == 'cost' ? next.copyWith(markup: markupOf(cost, next.selling)) : next;
}

/// What gets saved: the decoded cost, both prices ÷ how many when a count is given.
({String cost, String selling, String? error}) resolve(PriceInput p, CostCode? code) {
  var cost = p.cost.trim();
  if (code != null) {
    final d = code.decode(cost);
    if (d.error != null) return (cost: '', selling: '', error: d.error);
    cost = d.value;
  }
  final selling = p.selling.trim();
  final per = p.per.trim();
  if (per.isEmpty) return (cost: cost, selling: selling, error: null);
  final n = double.tryParse(per);
  if (n == null) return (cost: '', selling: '', error: 'How many must be a number');
  if (n == 0) return (cost: cost, selling: selling, error: null);
  String div(String v, int places) => v.isEmpty ? '' : trimDec(_num(v) / n, places);
  return (cost: div(cost, 4), selling: div(selling, 2), error: null);
}
