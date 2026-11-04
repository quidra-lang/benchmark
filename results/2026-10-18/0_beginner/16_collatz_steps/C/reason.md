# Task B selection: 16_collatz_steps / C

For start 1 the initial state already fails the loop guard, so the count remains zero while the maximum remains 1. For start 6, halving an even value or taking three times an odd value plus one yields 3, 10, 5, 16, 8, 4, 2, 1. This is eight updates and the maximum is 16. The peak includes the starting number before any increment.

The indexed input is copied to n, m starts at that same value, and k starts at zero. The comparison and assignment update m only when n exceeds it.

Complete main.c lines: 6, 7, 8, 9, 10, 11. The question supplies the two starting numbers, so keeping the separate input collection or its iteration would cost at least 31 more tokens without changing the trace. The output format is not part of the question. The benchmark tokenizer counts 113 tokens in this excerpt.
