import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/settings/secret_transfer.dart';

void main() {
  final list = [(name: 'Main', secret: 's3cret-main'), (name: 'Reseller A', secret: 'abc')];

  test('a sealed copy opens with the same passphrase only', () async {
    final text = await sealSecrets(list, 'correct horse');
    expect(text, startsWith('KSEC1:'));
    expect(text.contains('s3cret'), isFalse);
    expect(await openSecrets(text, 'correct horse'), list);
    await expectLater(openSecrets(text, 'wrong one'), throwsA(isA<WrongPassphrase>()));
  });

  test('anything else is not a copy', () async {
    await expectLater(openSecrets('hello', 'x'), throwsFormatException);
  });

  test('merge adds new names and replaces same names', () {
    final got = mergeSecrets([(name: 'Main', secret: 'old'), (name: 'B', secret: 'b')], list);
    expect(got, [(name: 'Main', secret: 's3cret-main'), (name: 'B', secret: 'b'), (name: 'Reseller A', secret: 'abc')]);
  });
}
