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

  test('the app opens with its own hourly code, worked out from a seed alone', () {
    final seed = seedFor('test-secret', 'fc1a79f7');
    expect(pinFromSeed(seed, at(1762560000)), '630113');
    expect(validPin(seed, '859129', at(1762563600)), isTrue);
    expect(validPin(seed, '630113', at(1762563600)), isTrue, reason: 'the last hour too (a clock at the edge)');
    expect(validPin(seed, '123456', at(1762563600)), isFalse);
    expect(validPin(seed, '', at(1762563600)), isFalse);
  });
}
