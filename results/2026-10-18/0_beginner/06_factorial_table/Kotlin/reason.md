# Task B selection: 06_factorial_table / Kotlin

## Answer requirements

Locate the factorial range and determine which representation, operations or output would need to change to preserve exact results through 15!.

## Evidence and answer

Change the inclusive 0..12 range to end at 15. The initializer 1 gives factorial type Int; use Long to hold 15! = 1307674368000. Long multiplication accepts an Int factor without changing the loop variable or the existing update expression, and normal string interpolation prints the full integer. The update and the output line are unchanged.

## Minimization

Selected complete lines of `main.kt`: 2, 3. The excerpt preserves their text, indentation and order.

The loop header alone does not reveal the integer representation. Selecting the full loop body adds unchanged calculations or output that do not introduce another edit. The previous excerpt contained 43 tokens; the selected excerpt contains **25 tokens** using `metric/tokenizer.py`.

## Current token measurement

Task A: **71 tokens**. Task B: **25 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
