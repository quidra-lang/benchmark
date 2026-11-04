# Task B selection: 22_char_frequency / C#

Count uppercase and lowercase ASCII letters separately, ignore other characters, and print only present letters in uppercase-then-lowercase order with their original case and line format.

The 26 counters use a lowercased ASCII index; remove lowercasing, allocate 52 slots and encode uppercase first, then lowercase. The loop bound and reconstruction must match that mapping. Preserve the positive-count guard and interpolated case.

Complete Program.cs lines: 6, 8, 10, 11, 13, 15, 16. Retain the folding, eligibility, counter and output evidence rather than inferring case, ordering or sparsity from a variable name. Unchanged setup and source text are unnecessary unless a complete line combines them with a necessary operation. The benchmark tokenizer counts 144 tokens in this excerpt.
