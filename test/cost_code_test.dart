import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/input/cost_code.dart';

final example = CostCode({0: 'ix', 1: 'r', 2: 'e', 3: 's', 4: 'u', 5: 'l', 6: 'o', 7: 'n', 8: 'a', 9: 'b'});

void main() {
  test('letters become their digits, any case, every letter of a digit', () {
    expect(example.decode('ESX').value, '230');
    expect(example.decode('ESX').error, isNull);
    expect(example.decode('esi').value, '230');
  });

  test('digits and a point pass through; empty stays empty', () {
    expect(example.decode('ES.X').value, '23.0');
    expect(example.decode('230').value, '230');
    expect(example.decode('').value, '');
    expect(example.decode(' ESX ').value, '230');
  });

  test('a letter not in the code is an error naming it', () {
    expect(example.decode('ESQ').error, "'q' isn't in this shop's code");
  });

  test('the same letter on two digits is a problem', () {
    expect(CostCode({0: 'ix', 3: 'sx'}).problem(), "'x' is on both 0 and 3");
    expect(example.problem(), isNull);
  });

  test('json round trip; empty json is an empty code', () {
    final back = CostCode.fromJson(example.toJson());
    expect(back.decode('ESX').value, '230');
    expect(back.letters, example.letters);
    expect(CostCode.fromJson('').isEmpty, isTrue);
    expect(CostCode.fromJson('{}').isEmpty, isTrue);
    expect(example.hasLetters('ESX'), isTrue);
    expect(example.hasLetters('23.5'), isFalse);
  });

  test('spaces in the cheat sheet are ignored; a digit or point as a letter is a problem', () {
    final c = CostCode({0: 'i x', 2: ' e ', 3: 's'});
    expect(c.letters[0], 'ix');
    expect(c.decode('ESX').value, '230');
    expect(CostCode({0: 'i5'}).problem(), "0 has '5': use letters only");
    expect(CostCode({0: 'i.'}).problem(), "0 has '.': use letters only");
  });
}
