# Task B selection — Dart

## Answer requirements shared across languages

1. Identify VOLUME tier selection at an upper limit and one unit above it, including the whole-usage charge and final-tier behavior.
2. Trace current metered usage into PREVIEW line items and the subtotal, including the applicable preview branch and next-period plan/seats.
3. Trace eligible discount, tax on the discounted subtotal, credit and amount due, preserving integer rounding and bounds.
4. Establish from the selected handoffs and operations that PREVIEW does not close usage, consume coupon applications, debit stored credit, or issue an invoice.

## Selected source locations

- `main.dart`: 41, 43, 46, 47, 48, 49, 50, 51, 125, 126, 127, 128, 190, 191, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 255, 256, 257, 258, 259, 260, 261, 262, 263, 264, 265, 266, 267, 268, 269, 270, 271, 272, 273, 274, 275, 276, 277, 278, 279, 280, 281, 282, 283, 284, 285, 286, 287, 288, 289, 290, 291, 292, 293, 294, 295, 296, 693, 694, 695, 696, 697, 698, 699, 700, 701, 702, 745, 746, 747, 748, 749, 750, 751, 752, 753, 754, 755, 756, 757, 758, 759, 760, 761, 762, 763, 764, 765, 766, 767, 768, 769, 770, 771, 772

## Evidence and language semantics

VOLUME iterates tiers in order and accepts the first tier whose inclusive upper limit contains the usage; the final or unbounded tier also accepts larger usage. Thus U uses the tier ending at U, whereas U+1 moves to the next tier and charges its unit price for the entire usage plus that tier's flat fee. This is not marginal GRADUATED pricing. The preview uses the existing usage and current plan for usage items, then adds the applicable opening or next-period charge. Renewal can use pending plan/seats for the next-period item; cancellation at period end has only final usage, and a trial opening uses opening items. Subtotal is the sum of newly constructed item amounts. A usable coupon gives either a percentage discount truncated after division by 10000 or a fixed discount capped at subtotal. Tax is truncated on the discounted subtotal, total adds that tax, credit is capped by total, and due is total minus credit. The selected preview path outputs these projected values without calling invoice issuance. Its item/totals operations use local result values; stored usage, coupon uses and customer balance are not assigned on this path.

The named close parameter defaults to false. LineItem stores an int amount, ~/ performs truncating integer division, and each builder returns a fresh list. The only subscription.usage assignment is guarded by close, and invoiceTotals only constructs a Totals result.

## Minimization and alternatives

Compared a tier-only excerpt with one including its caller: the tier boundary alone cannot establish preview composition, totals or the non-closing handoff. The selected VOLUME branch, relevant projection branches, item builders and totals computation together cover all four requirements. GRADUATED accumulation, invoice creation/payment/retry implementations, configuration parsing and unrelated commands do not help answer this interaction question and are omitted. Where a shared usage helper can close usage, retain the close parameter/default and guarded write; a call name alone would not establish that it stays open. Read-only parameter/value guarantees are used where present, but reference-based helpers are checked for actual writes. No proposed program modification is made.

The excerpt contains 1719 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
