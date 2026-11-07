# Task B selection: 16_collatz_steps / Rust

For start 1 the initial state already fails the loop guard, so the count remains zero while the maximum remains 1. For start 6, halving an even value or taking three times an odd value plus one yields 3, 10, 5, 16, 8, 4, 2, 1. This is eight updates and the maximum is 16. The peak includes the starting number before any increment.

The initializer binds the current and peak values to the incoming starting number and initializes the step count to zero. The guard, next-value expression, increment and maximum update show the order of operations.

Complete main.rs lines: 3, 4, 5, 6, 7. The question supplies the two starting numbers, so keeping the separate input collection or its iteration would cost at least 33 more tokens without changing the trace. The output format is not part of the question. The benchmark tokenizer counts 116 tokens in this excerpt.

## Current token measurement

Task A: **196 tokens**. Task B: **116 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
