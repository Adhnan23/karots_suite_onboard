import 'package:flutter/widgets.dart';

import 'data/db.dart';
import 'data/models.dart';
import 'settings/secrets.dart';
import 'settings/secure.dart';
import 'suite/client.dart';
import 'theme/mode.dart';

/// What every screen reaches: the database, the secret store, and the signed-in
/// session per shop.
class AppState extends ChangeNotifier {
  AppState(this.db, this.store, [ModeController? mode]) : mode = mode ?? ModeController(store);
  final Db db;
  final KeyStore store;

  /// Light, dark or the device's; the page heads carry the switch.
  final ModeController mode;
  final _sessions = <String, SuiteClient>{};

  SuiteClient? session(Shop s) => _sessions[s.uid];
  bool connected(Shop s) => _sessions.containsKey(s.uid);

  /// Signs in as the system user; fills the shop's install id the first time.
  Future<SuiteClient> connect(Shop s) async {
    final c = SuiteClient(s.address);
    final info = await c.loginInfo();
    if (s.installId.isEmpty || s.installId != info.installId) {
      s.installId = info.installId;
      await db.saveShop(s);
    }
    final secret = await Secrets(store).forShop(s);
    await c.signIn(secret, s.installId);
    _sessions[s.uid] = c;
    notifyListeners();
    return c;
  }

  void disconnect(Shop s) {
    _sessions.remove(s.uid);
    notifyListeners();
  }

  void changed() => notifyListeners();
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);
  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOrThrow<AppScope>().notifier!;
}

extension on BuildContext {
  T dependOnInheritedWidgetOrThrow<T extends InheritedWidget>() => dependOnInheritedWidgetOfExactType<T>()!;
}
