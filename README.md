# Karots Suite Onboard

The setup team's own app for Karots Suite (Android, Linux and Windows): one catalogue for every
kind of shop, fed by pulling the shops already running the Suite, used to set up new
shops and to add to or change running ones as their system user.

- **Shops:** a profile per shop (address on Tailscale or the shop's Wi-Fi, kind of shop).
  Connect signs in as the system user; the hourly PIN is worked out from the support
  secret. Pull reads products, packs, suppliers, plugins, categories, units, Product Plus
  fields, Alternatives and the AI Assistant's settings.
- **Review:** what a pull found that the catalogue hasn't got: accept, fix or drop.
  Known products (any barcode, or the same name) are skipped.
- **Catalogue:** search, filter by kind of shop, edit.
- **A shop's products:** new (from the catalogue or typed), or changes to one it has:
  supplier (the shop's, the catalogue's, a new one or none), prices, packs, extra
  barcodes, custom fields, and old stock (none, one batch, or several batches each with
  expiry and prices). Old stock goes in through stock intake: no bill, no money.
  Offline, work waits and is pushed later.
- **Every field reads from a photo** (Android camera; Linux: a picture file with
  `tesseract` installed); barcodes scan on Android.
- **AI Identify:** connected, the shop's own AI Assistant answers with its settings and
  key; offline, the same prompt is built here to copy into a chatbot.
- **Duplicates:** in the catalogue, or inside a connected shop (the Suite's own merge).
- **Alternatives:** see a shop's groups, make one, or copy one from another shop.
- **Export sheets:** products (with custom fields) and suppliers in the Suite's import format.

## First run

The app has its own install ID, **3EE0E57C** (shown on the lock), and opens with that
ID's hourly code, like a shop's system user or the Demo Room: from the PIN app, or
`make support-pin ID=3EE0E57C` in Karots Suite. Nothing to set up first. Then add the
support secret(s) under the key icon on Shops: they stay in this device's secure storage
and are never in a backup or a sync. To move them, use the share icon there (Send to
another device): a copy sealed with a passphrase (AES-256-GCM, PBKDF2), which the other
device opens with Add from another device. On Android the phone's own unlock opens the
app too (fingerprint, or its PIN / pattern).

The app carries only its ID's seed (`lib/lock/app_identity.dart`), never the secret.

## Suppliers and Quick add

- **Supplier lists:** Suppliers → a supplier → Download template (the standard CSV:
  name, barcode, extra_barcodes, unit, price, packs, plus any extra columns as details) →
  Import list. Products the catalogue has get their gaps filled and that supplier; new ones
  wait in Review. A product has one usual supplier, or none; no cost is kept (it's typed
  at the shop).
- **Quick add** (a shop's first action): scan or search, cost / price / quantity / expiry,
  next. It brings the product's supplier and unit into the shop when they're missing.

## Typing prices

- **Markup ×** (Onboard and Shelf): cost × markup = selling price; type the selling price and the
  markup follows (the same rules as the Suite's product form). With no cost typed, markup and selling price
  work the cost out (selling ÷ markup), in either order. Nothing about it is saved. Commas and spaces in a price are ignored.
- **÷ how many** (Onboard and Shelf, optional): a box's printed cost and price ÷ the pieces in it
  give one piece's (both to 2 decimals). Quantity is never touched and no Pack is made.
- **Cost code** (Onboard only): some shops write costs as letters (0 = i or x, 1 = r …). Fill the
  shop's cheat sheet in once under **Edit shop → Cost code**; every cost box at that shop then takes
  the letters: each one turns into its digit as it's typed, so the box shows `230` and the
  letters typed (`ESX`) show under it to check against the goods. Only the number is saved. The code travels with
  team sync and backups; Shelf never sees it.

## Team, backup and sync

- **Team:** devices that join one team key keep the same catalogue, suppliers and shops
  by themselves on the same Wi-Fi (every 2 minutes and soon after a change, while open).
- **Backup:** export a file of everything but the secrets; importing merges it.
- **Sync with a device:** one-off, by address and a 6-digit code.
- While connected to a shop, the app pulls it every 2 minutes and after each push.

## Build

    flutter build linux          # build/linux/x64/release/bundle/
    flutter build windows        # on Windows; or GitHub Actions → Windows build (no install here)
    flutter build apk --release --flavor onboard -t lib/main.dart       # app-onboard-release.apk
    flutter build apk --release --flavor shelf -t lib/main_shelf.dart   # app-shelf-release.apk (Karots Shelf)

The same code builds a second Android app, **Karots Suite Shelf** (home screen: Karots Shelf), for a
shop's own staff: one shop, signed in with their own phone number and PIN, no catalogue
(`lib/shelf/`, `isShelf` in `lib/flavor.dart`). Android needs `--flavor`; Linux and Windows are always Onboard. Windows: no camera or photo reading (a USB scanner types barcodes in).

## Tests

    flutter test
    LIVE_SUITE=http://localhost:3000 flutter test test/live_test.dart   # a dev Suite with every plugin
    SHOTS=/some/dir flutter test test/shots_test.dart                   # screen pictures, light and dark

The Suite side: `GET /api/v1/admin/products/packs` and `?ids=1` on the products export
(Karots Suite, 2026-11-08). Prompts in `lib/ai/prompts.dart` mirror the Suite's AI
Assistant; copy them over when those change.
