import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/suite/support_pin.dart';

DateTime at(int unix) => DateTime.fromMillisecondsSinceEpoch(unix * 1000, isUtc: true);

void main() {
  test('same codes as the Suite (internal/support/pin.go)', () {
    expect(supportPin('test-secret', ' fc1a79f7 ', at(1762560000)), '630113');
    expect(supportPin('test-secret', 'FC1A79F7', at(1762563599)), '630113');
    expect(supportPin('test-secret', 'fc1a79f7', at(1762563600)), '859129');
  });
  test('this hour first, then the last one (a clock at the hour edge)', () {
    expect(supportPinsNow('test-secret', 'fc1a79f7', at(1762563600)), ['859129', '630113']);
  });
}
