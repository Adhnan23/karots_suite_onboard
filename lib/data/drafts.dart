import '../sync/push.dart';
import 'models.dart';

/// Unsaved new products, so going back doesn't lose them: New product brings the
/// draft back until it's saved or started over.
// ponytail: kept in memory only (lost when the app is closed); keep them in the db if that bites.
CatalogProduct? catalogNewDraft;

/// A shop's unsaved New product, by shop uid, with its supplier choice.
final shopNewDrafts = <String, ({Draft draft, String supplier})>{};
