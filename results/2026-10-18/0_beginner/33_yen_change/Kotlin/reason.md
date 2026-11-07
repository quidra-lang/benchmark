# Task B selection: 33_yen_change / Kotlin

Trace the nonzero denomination counts for the given amount, show why zero counts are suppressed, and derive the complete printed line.

At face values 500, 5 and 1, quotient and remainder give (1, 6), (1, 1), and (1, 0). Every other face value yields a zero quotient. The conditional omits zero-count fragments; the accumulator sums the nonzero counts, with zero terms making no difference in implementations that add every quotient. The result is `506 yen: 500x1 5x1 1x1 (3 pieces)`.

The question fixes the amount. Denomination order, remainder and quotient, initial totals, and the formatting and join or write operations are retained. Other amounts and the iteration that merely selects them can be omitted; standard quotient/remainder and string operations supply their usual meanings.

Source: `main.kt`, original lines 2, 4–13. The previous excerpt measures 251 tokens; this evidence set measures 204 tokens.

## Current token measurement

Task A: **262 tokens**. Task B: **203 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
