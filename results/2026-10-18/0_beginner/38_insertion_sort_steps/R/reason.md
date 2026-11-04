# Task B selection: 38_insertion_sort_steps / R

Locate the predicate that controls right shifts, explain the strict comparison, and identify the existing loop and insertion behavior.

Shift only a preceding element strictly less than the saved value, keeping the existing prefix bound. If the code instead uses an early break, stop when the predecessor is greater than or equal to the saved value. On equality the earlier element stays before the new element, preserving stability. Leave the right shift, index decrement, one count increment per shift, insertion, and total accumulation in place. Keep the step loop and output calls, including the original spacing.

The saved key, predecessor index, shift and final insertion identify why the strict condition is sufficient for stability. The loop bound, any size dependency, and one-based output adjustment identify which positions it processes. The counting and output logic need no changes.

The internal positions are 2 through 8 and the print uses the index minus one, so the visible positions remain 1 through 7.

Source: `main.R`, original lines 3–5, 7–8, 10–12, 14. The previous excerpt measures 41 tokens; this evidence set measures 153 tokens.
