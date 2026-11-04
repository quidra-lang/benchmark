# Task B selection: 16_collatz_steps / Ruby

For start 1 the initial state already fails the loop guard, so the count remains zero while the maximum remains 1. For start 6, halving an even value or taking three times an odd value plus one yields 3, 10, 5, 16, 8, 4, 2, 1. This is eight updates and the maximum is 16. The peak includes the starting number before any increment.

The parallel assignment initializes n, steps and maximum from start, zero and start; until executes only while n is not one. The array max selects the larger of the old maximum and the new n.

Complete main.rb lines: 2, 3, 4, 5, 6. The question supplies the two starting numbers, so keeping the separate input collection or its iteration would cost at least 27 more tokens without changing the trace. The output format is not part of the question. The benchmark tokenizer counts 78 tokens in this excerpt.
