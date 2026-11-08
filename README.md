# Karots Suite Onboard

The setup team's own app for Karots Suite (Android and Linux): one catalogue for every
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

Choose an app PIN, then paste the support secret (`POS_SUPPORT_SECRET`). The secret stays
in the device's secure storage, behind the PIN (and fingerprint on Android).

## Build

    flutter build linux          # build/linux/x64/release/bundle/
    flutter build apk --release  # build/app/outputs/flutter-apk/app-release.apk

## Tests

    flutter test
    LIVE_SUITE=http://localhost:3000 flutter test test/live_test.dart   # a dev Suite with every plugin
    SHOTS=/some/dir flutter test test/shots_test.dart                   # screen pictures, light and dark

The Suite side: `GET /api/v1/admin/products/packs` and `?ids=1` on the products export
(Karots Suite, 2026-11-08). Prompts in `lib/ai/prompts.dart` mirror the Suite's AI
Assistant; copy them over when those change.
