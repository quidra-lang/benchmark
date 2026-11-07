# Task B selection: 38_insertion_sort_steps / Dart

Locate the predicate that controls right shifts, explain the strict comparison, and identify the existing loop and insertion behavior.

Shift only a preceding element strictly less than the saved value, keeping the existing prefix bound. If the code instead uses an early break, stop when the predecessor is greater than or equal to the saved value. On equality the earlier element stays before the new element, preserving stability. Leave the right shift, index decrement, one count increment per shift, insertion, and total accumulation in place. Keep the step loop and output calls, including the original spacing.

The saved key, predecessor index, shift and final insertion identify why the strict condition is sufficient for stability. The loop bound, any size dependency, and one-based output adjustment identify which positions it processes. The counting and output logic need no changes.

Source: `main.dart`, original lines 4–9, 11–12. The previous excerpt measures 47 tokens; this evidence set measures 123 tokens.

## Current token measurement

Task A: **244 tokens**. Task B: **123 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
