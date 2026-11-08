import 'package:flutter/widgets.dart';

import 'data/db.dart';
import 'data/models.dart';
import 'settings/secrets.dart';
import 'settings/secure.dart';
import 'suite/client.dart';
import 'sync/auto_pull.dart';
import 'sync/team.dart';
import 'sync/pull.dart';
import 'sync/push.dart';
import 'theme/mode.dart';

/// What every screen reaches: the database, the secret store, and the signed-in
/// session per shop.
const teamKeyName = 'team_key', deviceIdName = 'device_id';

class AppState extends ChangeNotifier {
  AppState(this.db, this.store, [ModeController? mode]) : mode = mode ?? ModeController(store);
  final Db db;
  final KeyStore store;

  /// Light, dark or the device's; the page heads carry the switch.
  final ModeController mode;
  final _sessions = <String, SuiteClient>{};

  /// The team sync, while this device is in a team (null otherwise).
  TeamSync? team;

  /// Joins or makes a team with this key (null leaves it) and starts syncing.
  Future<void> setTeam(String? key) async {
    await team?.stop();
    team = null;
    if (key == null || key.trim().isEmpty) {
      await store.write(teamKeyName, '');
    } else {
      await store.write(teamKeyName, key.trim().toUpperCase());
      var device = await store.read(deviceIdName) ?? '';
      if (device.isEmpty) {
        device = newUid();
        await store.write(deviceIdName, device);
      }
      final t = TeamSync(db, key: key, device: device)..addListener(notifyListeners);
      await t.start();
      team = t;
      db.onWrite = t.soon;
    }
    notifyListeners();
  }

  /// At unlock: back in the team this device was in.
  Future<void> resumeTeam() async {
    final key = await store.read(teamKeyName) ?? '';
    if (key.isNotEmpty) {
      try {
        await setTeam(key);
      } catch (_) {
        // the port may be taken; the Team page shows it isn't running
      }
    }
  }

  final _pullers = <String, AutoPuller>{};

  /// The shop's background pull while connected (null when not connected).
  AutoPuller? puller(Shop s) => _pullers[s.uid];

  /// Something was pushed to the shop: pull now, so the lists show it and the
  /// team's changes come along.
  void pushed(Shop s) => _pullers[s.uid]?.kick();

  SuiteClient? session(Shop s) => _sessions[s.uid];

  /// The one copy of a connected shop that its background pull keeps fresh; pages
  /// opened for it use this, so a save never puts back an older copy.
  Shop live(Shop s) => _live[s.uid] ?? s;
  final _live = <String, Shop>{};
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
    try {
      await c.signIn(secret, s.installId);
    } on SuiteError catch (e) {
      if (secret.isEmpty && e.status == 401) throw SuiteError(401, e.code, 'Add your support secret first: the key icon on Shops');
      rethrow;
    }
    _sessions[s.uid] = c;
    _live[s.uid] = s;
    _pullers.remove(s.uid)?.stop();
    // Work saved while out of reach goes first, then the pull brings the shop back.
    _pullers[s.uid] =
        AutoPuller(() async {
            await flushPending(db, c, s);
            await pull(db, c, s);
          })
          ..addListener(notifyListeners)
          ..start();
    notifyListeners();
    return c;
  }

  void disconnect(Shop s) {
    _sessions.remove(s.uid);
    _live.remove(s.uid);
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
