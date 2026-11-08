import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/input/scan.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

void main() {
  test('needs the same code three frames in a row', () {
    final c = ScanConfirm();
    expect(c.add(BarcodeFormat.code128, 'A1'), isNull);
    expect(c.add(BarcodeFormat.code128, 'A1'), isNull);
    expect(c.add(BarcodeFormat.code128, 'A1'), 'A1');
  });
  test('a different read in between starts again', () {
    final c = ScanConfirm();
    c.add(BarcodeFormat.code128, 'A1');
    c.add(BarcodeFormat.code128, 'A1');
    expect(c.add(BarcodeFormat.code128, 'B2'), isNull);
    expect(c.add(BarcodeFormat.code128, 'A1'), isNull);
  });
  test('EAN / UPC with a wrong check digit never counts', () {
    final c = ScanConfirm(needed: 1);
    expect(c.add(BarcodeFormat.ean13, '4006381333931'), '4006381333931');
    expect(c.add(BarcodeFormat.ean13, '4006381333932'), isNull);
    expect(c.add(BarcodeFormat.ean8, '96385074'), '96385074');
    expect(c.add(BarcodeFormat.upcA, '036000291452'), '036000291452');
    expect(c.add(BarcodeFormat.upcA, '03600029145'), isNull);
    // shop-made 13-digit Code 128 isn't checked
    expect(c.add(BarcodeFormat.code128, '1234567890123'), '1234567890123');
  });
}
