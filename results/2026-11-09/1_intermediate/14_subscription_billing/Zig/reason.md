# Task B selection — Zig

## Answer requirements shared across languages

1. Identify VOLUME tier selection at an upper limit and one unit above it, including the whole-usage charge and final-tier behavior.
2. Trace current metered usage into PREVIEW line items and the subtotal, including the applicable preview branch and next-period plan/seats.
3. Trace eligible discount, tax on the discounted subtotal, credit and amount due, preserving integer rounding and bounds.
4. Establish from the selected handoffs and operations that PREVIEW does not close usage, consume coupon applications, debit stored credit, or issue an invoice.

## Selected source locations

- `main.zig`: 40, 41, 42, 43, 46, 47, 48, 49, 95, 167, 168, 169, 170, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 318, 319, 320, 321, 322, 323, 324, 325, 326, 327, 328, 329, 330, 331, 332, 333, 334, 335, 336, 337, 338, 339, 340, 341

## Evidence and language semantics

VOLUME iterates tiers in order and accepts the first tier whose inclusive upper limit contains the usage; the final or unbounded tier also accepts larger usage. Thus U uses the tier ending at U, whereas U+1 moves to the next tier and charges its unit price for the entire usage plus that tier's flat fee. This is not marginal GRADUATED pricing. The preview uses the existing usage and current plan for usage items, then adds the applicable opening or next-period charge. Renewal can use pending plan/seats for the next-period item; cancellation at period end has only final usage, and a trial opening uses opening items. Subtotal is the sum of newly constructed item amounts. A usable coupon gives either a percentage discount truncated after division by 10000 or a fixed discount capped at subtotal. Tax is truncated on the discounted subtotal, total adds that tax, credit is capped by total, and due is total minus credit. The selected preview path outputs these projected values without calling invoice issuance. Its item/totals operations use local result values; stored usage, coupon uses and customer balance are not assigned on this path.

Preview explicitly passes false to usageItem; the guarded usage reset does not run. The locally initialized ArrayList receives fresh items through item(), and Totals has zero-valued i64 defaults. Mutable pointer signatures alone are insufficient, so retain the relevant helper writes and @divTrunc calculations.

## Minimization and alternatives

Compared a tier-only excerpt with one including its caller: the tier boundary alone cannot establish preview composition, totals or the non-closing handoff. The selected VOLUME branch, relevant projection branches, item builders and totals computation together cover all four requirements. GRADUATED accumulation, invoice creation/payment/retry implementations, configuration parsing and unrelated commands do not help answer this interaction question and are omitted. Where a shared usage helper can close usage, retain the close parameter/default and guarded write; a call name alone would not establish that it stays open. Read-only parameter/value guarantees are used where present, but reference-based helpers are checked for actual writes. No proposed program modification is made.

The excerpt contains 1936 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
