# Task B selection: 01_sum_max_min / C++

## Answer requirements

Trace the contribution of −23 and both occurrences of 5 to the sum and minimum.

## Evidence and answer

The array supplies the order and both occurrences of 5. The initial zero in std::accumulate and its full iterator range add both entries independently; std::minmax_element scans that same range and returns the minimum as its first component. Printing that component separately does not change the calculation of the minimum.

The prefix before −23 sums to 56; adding −23 gives 33, and the complete sum is 92. The preceding minimum is −8, which becomes −23 and is never lowered again. Addition counts both copies of 5; taking a minimum does not count duplicates.

## Minimization

Selected complete lines of `main.cpp`: 7, 8, 9. The excerpt preserves their text, indentation and order.

The longer alternative containing the output statements or formatter implementation adds presentation details but no new information about either reduction. The previous excerpt contained 165 tokens; the selected excerpt contains **121 tokens** using `metric/tokenizer.py`.

## Current token measurement

Task A: **199 tokens**. Task B: **117 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
