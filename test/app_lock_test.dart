import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/lock/app_lock.dart';
import 'package:karots_suite_onboard/settings/secure.dart';

void main() {
  test('the app PIN is kept as a hash and checked', () async {
    final store = MemoryStore();
    final lock = AppLock(store);
    expect(await lock.hasPin(), isFalse);
    await lock.setPin('4321');
    expect(await lock.hasPin(), isTrue);
    expect(await lock.check('4321'), isTrue);
    expect(await lock.check('1234'), isFalse);
    expect((await store.read(AppLock.key))!.contains('4321'), isFalse);
  });
}
