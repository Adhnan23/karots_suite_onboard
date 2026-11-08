import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/input/field_kind.dart';

void main() {
  test('numbers keep digits and one decimal point', () {
    expect(filterFor(FieldKind.number, 'Rs. 1,250.00/='), '1250.00');
    expect(filterFor(FieldKind.number, 'MRP 45'), '45');
    expect(filterFor(FieldKind.number, '12.5.3'), '12.53');
  });
  test('barcodes keep letters and digits only', () {
    expect(filterFor(FieldKind.barcode, ' 4 792 210 100 015 '), '4792210100015');
  });
  test('dates read the usual printed forms', () {
    expect(filterFor(FieldKind.date, 'EXP 12/2027'), '2027-12-31');
    expect(filterFor(FieldKind.date, 'Exp: 2027-02'), '2027-02-28');
    expect(filterFor(FieldKind.date, '31.12.27'), '2027-12-31');
    expect(filterFor(FieldKind.date, '05/03/2028'), '2028-03-05');
    expect(filterFor(FieldKind.date, '2028-03-05'), '2028-03-05');
    expect(filterFor(FieldKind.date, 'no date'), '');
  });
  test('text stays as picked, tidied', () {
    expect(filterFor(FieldKind.text, '  Panadol   Extra '), 'Panadol Extra');
  });
}
