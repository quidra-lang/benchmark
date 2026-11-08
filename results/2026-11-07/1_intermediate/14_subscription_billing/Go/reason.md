# Task B selection — Go

## Answer requirements shared across languages

1. Identify VOLUME tier selection at an upper limit and one unit above it, including the whole-usage charge and final-tier behavior.
2. Trace current metered usage into PREVIEW line items and the subtotal, including the applicable preview branch and next-period plan/seats.
3. Trace eligible discount, tax on the discounted subtotal, credit and amount due, preserving integer rounding and bounds.
4. Establish from the selected handoffs and operations that PREVIEW does not close usage, consume coupon applications, debit stored credit, or issue an invoice.

## Selected source locations

- `main.go`: 53, 54, 55, 56, 57, 58, 78, 79, 80, 81, 82, 83, 85, 87, 88, 89, 90, 91, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 281, 282, 283, 284, 285, 286, 287, 288, 289, 290, 291, 323, 324, 325, 326, 327, 328, 329, 330, 331, 332, 333, 334, 335, 336, 337, 338, 339, 340, 341, 342, 343, 344, 345, 346, 347, 348, 349, 350, 351, 352, 353, 354, 355, 356, 357, 358, 359, 360, 361, 362, 363, 364, 365, 366, 367, 368, 369, 370, 371, 372, 373, 374, 375, 376, 377, 378, 949, 950, 951, 952, 953, 954, 955, 956, 957, 958, 1026, 1027, 1028, 1029, 1030, 1031, 1032, 1033, 1034, 1035, 1036, 1037, 1038, 1039, 1040, 1041, 1042, 1043, 1044, 1045, 1046, 1047, 1048, 1049, 1050, 1051, 1052, 1053, 1054, 1055, 1056, 1057, 1058, 1059, 1060, 1061, 1062, 1063, 1064

## Evidence and language semantics

VOLUME iterates tiers in order and accepts the first tier whose inclusive upper limit contains the usage; the final or unbounded tier also accepts larger usage. Thus U uses the tier ending at U, whereas U+1 moves to the next tier and charges its unit price for the entire usage plus that tier's flat fee. This is not marginal GRADUATED pricing. The preview uses the existing usage and current plan for usage items, then adds the applicable opening or next-period charge. Renewal can use pending plan/seats for the next-period item; cancellation at period end has only final usage, and a trial opening uses opening items. Subtotal is the sum of newly constructed item amounts. A usable coupon gives either a percentage discount truncated after division by 10000 or a fixed discount capped at subtotal. Tax is truncated on the discounted subtotal, total adds that tax, credit is capped by total, and due is total minus credit. The selected preview path outputs these projected values without calling invoice issuance. Its item/totals operations use local result values; stored usage, coupon uses and customer balance are not assigned on this path.

Both usage calls explicitly pass false. New []Item literals are independent of subscription state, Totals starts with zero-valued int fields, and integer division truncates. Pointer parameters permit mutation, so the selected lookup/build/totals bodies supply the actual no-write evidence.

## Minimization and alternatives

Compared a tier-only excerpt with one including its caller: the tier boundary alone cannot establish preview composition, totals or the non-closing handoff. The selected VOLUME branch, relevant projection branches, item builders and totals computation together cover all four requirements. GRADUATED accumulation, invoice creation/payment/retry implementations, configuration parsing and unrelated commands do not help answer this interaction question and are omitted. Where a shared usage helper can close usage, retain the close parameter/default and guarded write; a call name alone would not establish that it stays open. Read-only parameter/value guarantees are used where present, but reference-based helpers are checked for actual writes. No proposed program modification is made.

The excerpt contains 2017 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
