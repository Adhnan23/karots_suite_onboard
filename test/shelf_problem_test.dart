import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karots_suite_onboard/shelf/shelf_app.dart';
import 'package:karots_suite_onboard/suite/client.dart';

void main() {
  test('a refused sign-in at unlock says why; being offline says nothing', () {
    expect(
      connectProblem(SuiteError(403, 'SHELF_NO_ACCESS', 'Ask the owner to give you Karots Shelf (Users page)')),
      'Ask the owner to give you Karots Shelf (Users page)',
    );
    expect(
      connectProblem(SuiteError(401, 'UNAUTHORIZED', 'Wrong phone number or PIN')),
      "Your PIN was changed on the shop's PC: lock, then sign in again with the new one",
    );
    expect(
      connectProblem(SuiteError(403, 'PIN_CHANGE_REQUIRED', "Change your PIN on the shop's PC first")),
      "Change your PIN on the shop's PC first",
    );
    expect(connectProblem(const SocketException('no route')), '');
  });
}
