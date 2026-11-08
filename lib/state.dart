import 'package:flutter/widgets.dart';

import 'data/db.dart';
import 'data/models.dart';
import 'settings/secrets.dart';
import 'settings/secure.dart';
import 'suite/client.dart';
import 'sync/auto_pull.dart';
import 'sync/pull.dart';
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
  final _pullers = <String, AutoPuller>{};

  /// The shop's background pull while connected (null when not connected).
  AutoPuller? puller(Shop s) => _pullers[s.uid];

  /// Something was pushed to the shop: pull now, so the lists show it and the
  /// team's changes come along.
  void pushed(Shop s) => _pullers[s.uid]?.kick();

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
    _pullers.remove(s.uid)?.stop();
    _pullers[s.uid] = AutoPuller(() => pull(db, c, s))
      ..addListener(notifyListeners)
      ..start();
    notifyListeners();
    return c;
  }

  void disconnect(Shop s) {
    _sessions.remove(s.uid);
    _pullers.remove(s.uid)?.stop();
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
