import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/backup.dart';

/// Pulls a connected shop by itself, so a team sees each other's work: every 2
/// minutes and right after a push; never two at once; stops on disconnect. A
/// failure is kept for the screen, never thrown.
class AutoPuller extends ChangeNotifier {
  AutoPuller(this._pull, {this.every = const Duration(minutes: 2)});
  final Future<void> Function() _pull;
  final Duration every;
  Timer? _timer;
  bool running = false;
  DateTime? last;
  String error = '';

  /// What the running pull is doing (null: none running); the pull fills it.
  final step = ValueNotifier<SyncStep?>(null);

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(every, (_) => kick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Pulls now unless one is already running.
  Future<void> kick() async {
    if (running) return;
    running = true;
    notifyListeners();
    try {
      await _pull();
      last = DateTime.now();
      error = '';
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      running = false;
      step.value = null;
      notifyListeners();
    }
  }
}
