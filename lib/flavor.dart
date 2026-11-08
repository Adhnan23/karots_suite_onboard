import 'package:flutter/services.dart';

/// Karots Suite Shelf (a shop's own staff, one shop) rather than Onboard: built
/// with --flavor shelf.
bool get isShelf => appFlavor == 'shelf';
