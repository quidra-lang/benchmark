# Task B selection: 01_sum_max_min / Java

## Answer requirements

Trace the contribution of −23 and both occurrences of 5 to the sum and minimum.

## Evidence and answer

The int array fixes the order and contains two 5s. Arrays.stream(values).summaryStatistics() computes the sum and minimum over the full stream under the IntSummaryStatistics contract. The getter and println lines only present results the standard operation already establishes.

The prefix before −23 sums to 56; adding −23 gives 33, and the complete sum is 92. The preceding minimum is −8, which becomes −23 and is never lowered again. Addition counts both copies of 5; taking a minimum does not count duplicates.

## Minimization

Selected complete lines of `Main.java`: 5, 6. The excerpt preserves their text, indentation and order.

The longer alternative containing the output statements or formatter implementation adds presentation details but no new information about either reduction. The previous excerpt contained 121 tokens; the selected excerpt contains **71 tokens** using `metric/tokenizer.py`.

## Current token measurement

Task A: **182 tokens**. Task B: **70 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
