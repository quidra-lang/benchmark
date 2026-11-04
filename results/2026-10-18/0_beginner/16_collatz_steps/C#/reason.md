# Task B selection: 16_collatz_steps / C#

For start 1 the initial state already fails the loop guard, so the count remains zero while the maximum remains 1. For start 6, halving an even value or taking three times an odd value plus one yields 3, 10, 5, 16, 8, 4, 2, 1. This is eight updates and the maximum is 16. The peak includes the starting number before any increment.

The assignments initialize n and maximum to start and steps to zero; the while guard is checked before the ternary transition, increment and Math.Max update.

Complete Program.cs lines: 8, 9, 10, 12, 13, 14. The question supplies the two starting numbers, so keeping the separate input collection or its iteration would cost at least 37 more tokens without changing the trace. The output format is not part of the question. The benchmark tokenizer counts 98 tokens in this excerpt.
