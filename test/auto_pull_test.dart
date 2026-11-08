import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/sync/auto_pull.dart';

void main() {
  test('pulls every 2 minutes and right after a push, never two at once, stops on disconnect', () {
    fakeAsync((t) {
      var pulls = 0;
      final gate = Completer<void>();
      var slow = false;
      final a = AutoPuller(() async {
        pulls++;
        if (slow) await gate.future;
      });
      a.start();
      t.elapse(const Duration(minutes: 1, seconds: 59));
      expect(pulls, 0);
      t.elapse(const Duration(seconds: 1));
      expect(pulls, 1);
      a.kick(); // after a push
      t.flushMicrotasks();
      expect(pulls, 2);
      slow = true;
      a.kick();
      a.kick(); // one already running: no second at once
      t.flushMicrotasks();
      expect(pulls, 3);
      gate.complete();
      t.flushMicrotasks();
      expect(a.last, isNotNull);
      a.stop();
      t.elapse(const Duration(minutes: 10));
      expect(pulls, 3);
    });
  });

  test('a failed background pull is kept, not thrown; the next one clears it', () {
    fakeAsync((t) {
      var fail = true;
      final a = AutoPuller(() async {
        if (fail) throw Exception('shop not reachable');
      });
      a.kick();
      t.flushMicrotasks();
      expect(a.error, contains('shop not reachable'));
      fail = false;
      a.kick();
      t.flushMicrotasks();
      expect(a.error, isEmpty);
    });
  });
}
