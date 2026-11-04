# Task B selection: 16_collatz_steps / J

For start 1 the initial state already fails the loop guard, so the count remains zero while the maximum remains 1. For start 6, halving an even value or taking three times an odd value plus one yields 3, 10, 5, 16, 8, 4, 2, 1. This is eight updates and the maximum is 16. The peak includes the starting number before any increment.

The independent locals n and largest start at the supplied value, while steps starts at zero. The if/else ends before steps and largest are updated; >: increments and dyadic >. takes the maximum.

Complete main.ijs lines: 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13. The question supplies the two starting numbers, so keeping the separate input collection or its iteration would cost at least 22 more tokens without changing the trace. The output format is not part of the question. The benchmark tokenizer counts 96 tokens in this excerpt.
