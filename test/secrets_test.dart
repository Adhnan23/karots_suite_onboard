import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/data/models.dart';
import 'package:karots_suite_onboard/settings/secrets.dart';
import 'package:karots_suite_onboard/settings/secure.dart';

void main() {
  test('several named secrets; a shop uses its own, else the first', () async {
    final store = MemoryStore();
    await store.write(supportSecretKey, 'old-single'); // a device set up before names
    final s = Secrets(store);
    expect((await s.all()).map((x) => (x.name, x.secret)), [('Main', 'old-single')]);
    await s.save([...await s.all(), (name: 'Reseller A', secret: 'abc')]);
    expect(await s.forShop(Shop(name: 'x', secretName: 'Reseller A')), 'abc');
    expect(await s.forShop(Shop(name: 'x')), 'old-single');
    expect(await s.forShop(Shop(name: 'x', secretName: 'gone')), 'old-single');
  });
}
