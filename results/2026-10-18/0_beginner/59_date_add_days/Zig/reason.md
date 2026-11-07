# Task B selection: 59_date_add_days / Zig

## Common answer requirements

Subtract the original positive day count, reuse the Gregorian leap-year rule at backward boundaries, and change the printed operator while preserving date padding.

## Source evidence

The loop consumes the original positive count one iteration at a time, advancing the day and wrapping to the next month/year. Decrement the day instead; at zero move to the preceding month (December of the preceding year when crossing January), then use that month’s length in the resulting year. Reuse the shown Gregorian test for February. Change the operator from plus to minus, retaining the positive count and zero-padded dates.

## Minimization

Writer initialization does not affect the visible literal or its format arguments. The loop, rollover, Gregorian month length and output show the changed behavior.

Selected complete lines of `main.zig`: 14, 16–35. The prior excerpt measured 468 tokens; this excerpt measures 423 with `metric/tokenizer.py`.

## Current token measurement

Task A: **697 tokens**. Task B: **423 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
