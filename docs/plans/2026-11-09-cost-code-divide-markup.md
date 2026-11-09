# Cost code, divide helper and markup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Typing prices at a shop takes what's written on the goods: a shop's secret cost letters (Onboard only), an
optional "÷ how many" for box prices, and Markup × like the Suite's product form (both apps).

**Architecture:** Two pure Dart files hold all the arithmetic (`cost_code.dart`, `prices.dart`), unit-tested. The shop
record gets the code (DB v6, own timestamp so team sync carries edits). One `PriceFields` widget (cost, selling,
markup, ÷) replaces the cost/selling pair in ProductForm and Quick add; a `CostField` covers batch/lot cost boxes.
Fields keep what was typed; values are decoded when read, and Save refuses while a cost can't be read.

**Tech Stack:** Flutter / Dart, sqflite (ffi in tests), flutter_test.

**Spec:** `docs/specs/2026-11-09-cost-code-box-markup-design.md` (read it with this plan).

## Global Constraints

- Cost code: **Onboard only**. Every call site gets the code through `codeFor(shop)`, which is `null` when `isShelf`.
- A digit may have several letters; a letter means one digit; matched ignoring case; a typed `.` passes through.
- Only cost boxes take letters. Selling, wholesale, pack prices stay digits.
- What is saved / pushed is always the number, never letters. Markup and ÷ are never saved or sent.
- ÷ is **totally optional**: empty = boxes behave exactly as today. Never touches quantity. Never creates a Pack.
- Rounding: a derived **cost keeps up to 4 decimals**, a derived **selling price up to 2**; trailing zeros trimmed
  (`23`, `33.3333`, `12.5`). Markup shown to 2 places (Suite `price.ts`: selling ÷ cost).
- No Suite (karots-suite) changes. Packs untouched. Files ≤ 500 lines.
- Run tests with `flutter test <file>`; `flutter analyze` clean before each commit.

## Review Focus

1. **A code edited at home, then synced** — the other device must get it even though the shop wasn't pulled again
   (import today only takes a shop whose `lastPull` is newer). Test in Task 3.
2. **A cost typed with an unknown letter, then Save** — must refuse with the field's message, never push letters or
   an empty cost. Tests in Tasks 4 and 5.
3. **Shelf build** — a shop that has a code (synced in a backup) must still show plain number boxes in Shelf. Test in
   Task 4.
4. **÷ with a blank or zero count, or "0.5"** — blank/0 means no dividing; a non-number count is a field error, never a
   crash or division by zero. Test in Task 2.
5. **Editing an existing product** — opening a product with cost 23 and selling 30 shows markup 1.3 and an empty ÷;
   saving untouched gives back exactly 23 and 30. Test in Task 4.

---

### Task 1: Cost code (pure)

**Files:**
- Create: `lib/input/cost_code.dart`
- Test: `test/cost_code_test.dart`

**Interfaces:**
- Produces:
  - `class CostCode { CostCode(Map<int, String> letters); final Map<int, String> letters; }` — digit → its letters
    (`{0: 'ix', 1: 'r', …}`), stored lower-case.
  - `factory CostCode.fromJson(String s)` / `String toJson()` — JSON object `{"0":"ix","1":"r"}`; `''` / `'{}'` → empty.
  - `bool get isEmpty`
  - `String? problem()` — `null` when fine; `"'x' is on both 0 and 3"` when a letter repeats across digits.
  - `({String value, String? error}) decode(String typed)` — digits and `.` pass through; each letter → its digit;
    unknown letter → `error: "'q' isn't in this shop's code"`; result trimmed; `value` is the digit string.
  - `bool hasLetters(String typed)`

- [ ] **Step 1: Write the failing tests** — `test/cost_code_test.dart`, using the spec's example code
  `{0:'ix',1:'r',2:'e',3:'s',4:'u',5:'l',6:'o',7:'n',8:'a',9:'b'}`:
  - `decode('ESX')` → `value '230'`, no error; `decode('esi')` → `'230'` (case, both 0 letters);
  - `decode('ES.X')` → `'23.0'`; `decode('230')` → `'230'`; `decode('')` → `''`;
  - `decode('ESQ')` → `error "'q' isn't in this shop's code"`;
  - `CostCode({0:'ix', 3:'sx'}).problem()` → `"'x' is on both 0 and 3"`; the example code's `problem()` → `null`;
  - `fromJson(c.toJson())` round-trips; `fromJson('')` is empty.
- [ ] **Step 2:** `flutter test test/cost_code_test.dart` → FAIL (file missing).
- [ ] **Step 3:** Implement the class above.
- [ ] **Step 4:** `flutter test test/cost_code_test.dart` → PASS.
- [ ] **Step 5:** Commit `feat(prices): a shop's cost code decodes letters to digits`.

### Task 2: Prices arithmetic (pure)

**Files:**
- Create: `lib/input/prices.dart`
- Test: `test/prices_test.dart`

**Interfaces:**
- Consumes: `CostCode.decode` (Task 1).
- Produces:
  - `class PriceInput { String cost, selling, markup, per; }` — what's typed in the four boxes (`per` = ÷ how many).
  - `String markupOf(String cost, String selling)` — port of Suite `markupOf`: `''` unless both > 0; else
    selling ÷ cost rounded to 2 places, trailing zeros trimmed.
  - `PriceInput editPrice(PriceInput p, String field, String value, CostCode? code)` — port of Suite `editPrice`
    (field `'cost' | 'markup' | 'selling' | 'per'`; `'per'` only stores the value). Uses the **decoded** cost
    (letters allowed when `code` given); the derived selling is written as digits, 2 decimals, trimmed. The typed
    cost text is never rewritten.
  - `({String cost, String selling, String? error}) resolve(PriceInput p, CostCode? code)` — what gets saved:
    decode the cost (error passes up), then if `per` is blank or `0` keep as is, else divide both by `per`; cost
    up to 4 decimals, selling up to 2, trimmed. `per` not a number → `error: 'How many must be a number'`.
  - `String trimDec(double v, int places)`.

- [ ] **Step 1: Write the failing tests**:
  - `markupOf('100','115')` → `'1.15'`; `markupOf('','115')` → `''`;
  - `editPrice(cost '200', field 'markup', '1.15')` → selling `'230'`; then `field 'selling', '250'` → markup `'1.25'`;
  - with the Task 1 code: `editPrice(field 'cost', 'ESX', markup '1.15')` → selling `'264.5'`, cost stays `'ESX'`;
  - `resolve(cost 'ESX', selling '300', per '10', code)` → cost `'23'`, selling `'30'`;
  - `resolve(cost '100', selling '150', per '3')` → cost `'33.3333'`, selling `'50'`;
  - `resolve(per '')` and `resolve(per '0')` → unchanged values; `resolve(per 'abc')` → error;
  - `resolve(cost 'ESQ', code)` → the code's error; `resolve(cost '23', selling '30', per '')` → `'23'`, `'30'`
    exactly (Review Focus 5).
- [ ] **Step 2:** run → FAIL. **Step 3:** implement. **Step 4:** `flutter test test/prices_test.dart` → PASS.
- [ ] **Step 5:** Commit `feat(prices): markup and the divide helper, Suite price rules`.

### Task 3: The shop keeps its code (DB, backup, team sync)

**Files:**
- Modify: `lib/data/models.dart` (`Shop`: `costCodeJson`, `costCodeAt`, `toRow`, `fromRow`)
- Modify: `lib/data/db.dart` (version 6; `_create` + `_upgrade`: `ALTER TABLE shops ADD COLUMN cost_code TEXT`,
  `… ADD COLUMN cost_code_at TEXT`)
- Modify: `lib/data/backup.dart` (import: a shop that isn't newer still takes `cost_code` when its `cost_code_at`
  is newer than ours)
- Modify: `lib/input/cost_code.dart` (add `CostCode? codeFor(Shop shop)`: `null` when `isShelf` or the code is empty)
- Test: `test/cost_code_sync_test.dart`

**Interfaces:**
- Produces: `Shop.costCodeJson` (String, `''` = none), `Shop.costCodeAt` (DateTime?), `Shop.costCode` getter →
  `CostCode`; `codeFor(Shop) → CostCode?`.

- [ ] **Step 1: Write the failing tests** (style of `test/backup_test.dart`, in-memory ffi DB):
  - a shop saved with a code reads back with it; `exportBackup` contains it;
  - **device A and B share a shop with the same `lastPull`; A sets a code (newer `costCodeAt`); importing A's backup
    into B gives B the code** (Review Focus 1); and an older code never overwrites a newer one;
  - `codeFor` returns `null` after `setShelf(true)` for a shop with a code (reset with `setShelf(false)`).
- [ ] **Step 2:** run → FAIL. **Step 3:** implement. **Step 4:** `flutter test test/cost_code_sync_test.dart
  test/backup_test.dart test/team_test.dart test/db_test.dart` → PASS.
- [ ] **Step 5:** Commit `feat(shops): a shop's cost code, carried by backup and team sync`.

### Task 4: PriceFields and CostField widgets, in ProductForm

**Files:**
- Create: `lib/input/price_fields.dart`
- Modify: `lib/screens/product_form.dart` (Prices section: `PriceFields` instead of the cost/selling `_pair`; new
  param `CostCode? costCode`; `read()` uses `resolve`; new `String? problem()`)
- Modify: `lib/screens/shop_product_editor.dart:95` (`save()` → if `form.currentState!.problem()` is non-null, toast
  it as an error and return; pass `costCode: codeFor(s)` to `ProductForm`)
- Test: `test/widgets/price_fields_test.dart`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces:
  - `class CostField extends StatelessWidget { CostField({required String label, required TextEditingController controller, CostCode? code}) }`
    — `KsField` (OCR stays; number keyboard when `code == null`, text keyboard otherwise); under it, when the text
    has letters, helper `= 230` or the decode error as `errorText`.
  - `class PriceFields extends StatefulWidget { PriceFields({Key? key, required String cost, required String selling, CostCode? code}) }`
    with `PriceFieldsState.read() → ({String cost, String selling, String? error})` (= `resolve`). Layout: Cost |
    Selling on one row, Markup × | ÷ how many on the next, the ÷ box empty with hint `optional`; when ÷ has a count,
    helpers under Cost and Selling show `= 23 each` / `= 30 each`.
  - `ProductFormState.problem() → String?`.

- [ ] **Step 1: Write the failing widget tests**:
  - with the Task 1 code: type `ESX` in Cost → `= 230` shows; type `ESQ` → the error shows and `read().error` is set;
  - type `1.15` in Markup after Cost `200` → Selling shows `230`;
  - Cost `ESX`, Selling `300`, ÷ `10` → `read()` gives `23`, `30` and `= 23 each` shows;
  - `PriceFields(cost: '23', selling: '30')` opens with Markup `1.3`, ÷ empty, and `read()` gives `23`, `30`
    (Review Focus 5);
  - `code: null` → Cost has a number keyboard and letters show no helper (Shelf, Review Focus 3).
- [ ] **Step 2:** run → FAIL. **Step 3:** implement widgets, then wire `ProductForm` and `ShopProductEditor.save`.
- [ ] **Step 4:** `flutter test test/widgets/price_fields_test.dart test/widgets/drafts_test.dart
  test/widgets/catalog_test.dart` → PASS (catalogue form still works with `costCode` null).
- [ ] **Step 5:** Commit `feat(prices): markup, divide and the cost code in the product form`.

### Task 5: Quick add, stock batches and lots

**Files:**
- Modify: `lib/screens/quick_add_screen.dart:69-116` (`PriceFields(cost: '', selling: p.selling, code: codeFor(s))`
  instead of the Cost / Price row; on Add: `read()`; an error → toast, sheet stays open; pass the resolved values to
  `quickDraft`)
- Modify: `lib/screens/stock_editor.dart` (new param `CostCode? code`; cost box → `CostField`; `read()` decodes;
  `StockEditorState.problem() → String?`), and `shop_product_editor.dart` passes `code: codeFor(s)` and checks
  `stock.currentState?.problem()` in `save()`
- Modify: `lib/screens/lots_section.dart:79-105` (cost box → `CostField` with `codeFor(widget.shop)`; decode before
  `Navigator.pop`; an error keeps the dialog open)
- Test: `test/quick_add_test.dart` (add), `test/lots_test.dart` (add)

- [ ] **Step 1: Write the failing tests**: Quick add with the code, Cost `ESX`, ÷ `10`, Selling `300` → the queued /
  pushed draft has cost `23`, selling `30`, quantity exactly as typed (÷ never touches it); Cost `ESQ` → nothing
  queued, error shown (Review Focus 2); a batch cost `ESX` saves `230`; a lot cost `ESQ` keeps the dialog open.
- [ ] **Step 2:** run → FAIL. **Step 3:** implement. **Step 4:** `flutter test` (whole suite) → PASS;
  `flutter analyze` clean.
- [ ] **Step 5:** Commit `feat(prices): Quick add, batches and lots take the cost code and divide`.

### Task 6: Cost code editor on the shop (Onboard)

**Files:**
- Create: `lib/screens/cost_code_sheet.dart` — `Future<CostCode?> editCostCode(BuildContext, CostCode current)`:
  ten rows `0`…`9`, each a text box for that digit's letters (e.g. `ix`), live `problem()` shown, Save disabled while
  there is one, **Clear** empties the code.
- Modify: `lib/screens/shops_screen.dart` `editShop` — a **Cost code** row (shows `None` or `r e s u l …`) opening
  the sheet; hidden when `isShelf`; saving sets `costCodeJson` and `costCodeAt = now`.
- Test: `test/widgets/cost_code_sheet_test.dart`

- [ ] **Step 1: Write the failing widget test**: fill the example code → returned `CostCode` decodes `ESX` to `230`;
  put `x` on 0 and 3 → Save disabled and the message shows; Clear → empty code.
- [ ] **Step 2:** run → FAIL. **Step 3:** implement. **Step 4:** `flutter test` whole suite → PASS; analyze clean.
- [ ] **Step 5:** Commit `feat(shops): enter a shop's cost code from its cheat sheet`.

### Task 7: Look, docs, hand-off

- [ ] Run the app on Linux (`flutter run -d linux`, and `-t lib/main_shelf.dart` for Shelf); screenshot Quick add,
  the product Prices and the cost code sheet, light and dark; self-review them (fits a phone width, no overflow).
- [ ] README: a short "Cost code, ÷ and markup" note (Onboard: cost code; both: ÷ and markup).
- [ ] Build both APKs (`flutter build apk --flavor onboard` / `--flavor shelf -t lib/main_shelf.dart`), copy to
  `~/Downloads/karots-onboard.apk` and `karots-shelf.apk`.
- [ ] Delete this plan and the spec once the user is happy; commit.
