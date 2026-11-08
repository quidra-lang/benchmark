# Task B selection — Java

## Answer requirements shared across languages

1. Identify VOLUME tier selection at an upper limit and one unit above it, including the whole-usage charge and final-tier behavior.
2. Trace current metered usage into PREVIEW line items and the subtotal, including the applicable preview branch and next-period plan/seats.
3. Trace eligible discount, tax on the discounted subtotal, credit and amount due, preserving integer rounding and bounds.
4. Establish from the selected handoffs and operations that PREVIEW does not close usage, consume coupon applications, debit stored credit, or issue an invoice.

## Selected source locations

- `Main.java`: 46, 48, 51, 52, 53, 54, 55, 56, 57, 243, 244, 245, 246, 247, 248, 249, 258, 275, 276, 277, 278, 280, 281, 282, 283, 284, 285, 286, 288, 289, 290, 291, 292, 293, 294, 295, 296, 298, 299, 300, 301, 303, 304, 305, 306, 307, 308, 309, 310, 311, 312, 313, 314, 315, 316, 317, 715, 716, 717, 719, 720, 721, 722, 764, 765, 766, 767, 768, 769, 770, 771, 772, 773, 774, 775, 776, 777, 778, 779, 780, 781, 782, 783, 784, 785, 786, 787, 788, 789, 790, 791

## Evidence and language semantics

VOLUME iterates tiers in order and accepts the first tier whose inclusive upper limit contains the usage; the final or unbounded tier also accepts larger usage. Thus U uses the tier ending at U, whereas U+1 moves to the next tier and charges its unit price for the entire usage plus that tier's flat fee. This is not marginal GRADUATED pricing. The preview uses the existing usage and current plan for usage items, then adds the applicable opening or next-period charge. Renewal can use pending plan/seats for the next-period item; cancellation at period end has only final usage, and a trial opening uses opening items. Subtotal is the sum of newly constructed item amounts. A usable coupon gives either a percentage discount truncated after division by 10000 or a fixed discount capped at subtotal. Tax is truncated on the discounted subtotal, total adds that tax, credit is capped by total, and due is total minus credit. The selected preview path outputs these projected values without calling invoice issuance. Its item/totals operations use local result values; stored usage, coupon uses and customer balance are not assigned on this path.

Preview explicitly passes false to usageItems, bypassing its only usage reset. ArrayList line items and local long totals are newly constructed. Plan, Subscription and Customer are references, so the relevant helper bodies, not reference typing alone, establish the non-mutating path.

## Minimization and alternatives

Compared a tier-only excerpt with one including its caller: the tier boundary alone cannot establish preview composition, totals or the non-closing handoff. The selected VOLUME branch, relevant projection branches, item builders and totals computation together cover all four requirements. GRADUATED accumulation, invoice creation/payment/retry implementations, configuration parsing and unrelated commands do not help answer this interaction question and are omitted. Where a shared usage helper can close usage, retain the close parameter/default and guarded write; a call name alone would not establish that it stays open. Read-only parameter/value guarantees are used where present, but reference-based helpers are checked for actual writes. No proposed program modification is made. Whitespace-only lines outside source literals and explicit line continuations are omitted: they contribute tokens but no evidence for the answer. Literal content is preserved, and files with ambiguous quote or multiline-literal syntax are left unchanged by this step.

The excerpt contains 1852 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
