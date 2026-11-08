import 'package:flutter/services.dart';

/// Karots Suite Shelf (a shop's own staff, one shop) rather than Onboard: set by
/// lib/main_shelf.dart (any platform) or the Android --flavor shelf.
bool get isShelf => _shelf || appFlavor == 'shelf';
bool _shelf = false;

/// Shelf's entry point (and tests) say so here.
void setShelf(bool on) => _shelf = on;
