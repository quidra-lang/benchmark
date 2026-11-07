# Task B selection — 01_sum_max_min / Quidra

The array contains -23 once and 5 twice. Core `sum()` includes every element, so -23 contributes -23 to the total of 92, and the two occurrences of 5 contribute 10. Core `min()` selects the smallest element value, which is -23. Repeating 5 contributes another term to the sum but does not change the minimum.

Select source lines 1, 2, and 4 verbatim: the array declaration, the `println` call for the sum, and the `println` call for the minimum. The two output lines identify the Core operations and the labels under which their results are reported. The maximum output on line 3 is unrelated to the Task B question and is excluded.

Each selected line is necessary. Removing the array declaration loses the evidence for -23, the repeated 5, and the other values needed to establish the minimum. Removing either output line loses the corresponding operation and reported result. No other source line provides that information. Known Core library semantics establish how `sum()` and `min()` behave, so their implementations do not need to be included.

## Current token measurement

Task A: **89 tokens**. Task B: **74 tokens** across three complete source lines. Measured with `metric/tokenizer.py`, which counts contiguous `()` as one token.
