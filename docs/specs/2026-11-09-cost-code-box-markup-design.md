# Cost code, box prices and markup — design

Three small helpers for typing prices while setting up a shop. Written 2026-11-09 from a talk with the user.

## Why

Setting up a shop, the user reads prices off goods and boxes. Yesterday one product meant: decode the shop's secret cost
letters in his head, count the pieces in the box, divide on a calculator, then divide the selling price too, and
sometimes work out "cost × 1.15" when the box shows no selling price. Too many moving pieces. The apps should do the
arithmetic; he types what he sees.

## 1. Cost code — Onboard only

Some big shops write the cost on their goods as letters so customers can't read it (example cheat sheet:
0 = i or x, 1 = r, 2 = e, 3 = s, 4 = u, 5 = l, 6 = o, 7 = n, 8 = a, 9 = b). Each shop has its own; most shops have none.

- A shop in Onboard may have a **cost code**: for each digit 0–9, one or more letters. Filled in once from the shop's
  cheat sheet, on the shop's own settings / edit page. Empty = the shop has no code; nothing changes for it.
- **A digit can have several letters** (0 = i or x). The shops do this on purpose so the code is harder to guess. Each
  letter means exactly one digit; the same letter on two digits is refused when saving the code.
- Letters are matched ignoring case.
- **Every cost field at that shop** accepts letters: Quick add, the product's Prices (cost price), stock batches and
  lots (cost). Each letter turns into its digit as it is typed, so the box shows the number (**230**) and the letters
  typed ("ESX") show under it to check against the goods (user, 2026-11-09). Keyboard suggestions are off in
  a coded cost box. What is saved and sent to the Suite is the number, never the letters.
- A letter that isn't in the code shows a plain error on the field ("'q' isn't in this shop's code") and blocks Save
  of that field's value until fixed.
- A decimal point may be typed as-is (e.g. "ES.X" → 23.0); shops' codes don't cover the point.
- Only cost fields. Selling, wholesale and pack prices stay digits only.
- **Not in Karots Shelf** (the shop's own staff know their code), and not in the Suite. In Shelf the cost fields work
  exactly as today.
- The code travels with the shop record in Onboard's team sync and backup file, like the rest of the shop, so whoever
  on the team goes to that shop next has it.
- Camera reading of a cost (OCR) — **builder's call / later**: today number OCR keeps digits only; decoding letters
  read off a label is not required in this round.

## 2. Box → one piece — both apps

Medicines and other boxed goods show the price for the box, not for one piece. The shop sells pieces.

- Next to the cost and selling price (Quick add and the product's Prices), a **"÷ how many"** divide helper (only for dividing; works for any box, strip, packet…; **totally optional**: off by default, the boxes work exactly as today unless it is used): the
  user types the box's cost / selling price as printed plus how many pieces are in it, and the field's value becomes
  the per-piece price (box ÷ N). The result is shown before saving.
- One N per product form / Quick add entry applies to both cost and selling (they come off the same box).
- Works with the cost code in Onboard: "ESX for a box of 10" → 23.
- Saves the per-piece cost and selling only. **It does not create a Pack** (the user's shop doesn't want packing).
  Packs, the packs editor and everything pack-related stay untouched for shops that use them.
- N is not remembered; it is only a typing aid.
- **Quantity is untouched** (user): stock quantity is always typed in pieces in its own field; the box option never
  changes it.
- Only in Quick add and the product's Prices section (my call); stock batch / lot fields keep plain cost and price
  boxes (the cost code still works in their cost boxes in Onboard).
- Rounding (my call, matching the Suite's 4-decimal unit costs, migration 00030): per-piece **cost and selling round to 2 decimals**
  (100 ÷ 3 → 33.33; user, 2026-11-09).

## 3. Markup — both apps

The Suite's product form already has **Markup ×** (`web/src/features/admin/products/price.ts` in karots-suite): cost,
markup and selling, type any one and the others follow — cost or markup set the selling price; selling sets the
markup; markup = selling ÷ cost rounded to 2 places. Port the same behaviour to the apps' Prices section and Quick add.

- Use case: the box has no selling price and the shop says "selling is cost × 1.15": type 1.15, selling fills in.
- **No saved / default markup per shop** (user: "we should change it" — typed per product when needed). The box starts
  empty, or shows the markup worked out from an existing cost and selling price.
- Markup is never sent to the Suite; only cost and selling are.

## Non-goals

- No Packs created from box sizes; no change to Packs.
- No cost code in Shelf or the Suite; no letters stored anywhere but Onboard's shop record.
- No per-shop default markup.
- No Suite (karots-suite) changes at all.

## Left to the builder

- Exact layout of the cost-code editor (ten rows, letters typed per digit is fine) and of the box / markup controls,
  following the apps' existing kit (`lib/ui/kit.dart`, `KsField`, `Section`).
- Where the decode lives (a small pure function with unit tests: letters → digits, unknown letter, duplicates,
  decimal point, case) and how fields get the shop's code.
- DB migration for the shop's code (e.g. a JSON column on `shops`) and carrying it through team sync / backup.
- Rounding of the markup-derived selling price, matching the Suite's `price.ts`.
