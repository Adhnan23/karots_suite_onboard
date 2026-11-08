import 'package:flutter/material.dart';

import 'flavor.dart';
import 'screens/shop_actions.dart';
import 'shelf/shelf_app.dart';

/// Karots Suite Shelf: `flutter build apk --flavor shelf -t lib/main_shelf.dart`.
void main() {
  setShelf(true);
  registerShopActions();
  runApp(const ShelfApp());
}
