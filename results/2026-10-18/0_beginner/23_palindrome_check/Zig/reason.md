# Task B selection: 23_palindrome_check / Zig

For the source phrase `Step on no pets.`, the spaces and period are removed and the leading S is lowered, yielding `steponnopets`. The reverse or mirrored pairs match. The program prints the original phrase with the result: `Step on no pets. -> yes`.

The normalization writes ASCII lowercase letters to a separate buffer. The pair comparison starts with a true flag and sets it false on a mismatch. No mismatch occurs here; the break after a mismatch does not affect the trace.

Complete main.zig lines: 7, 12, 15, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 30, 31, 32. The original string binding, normalization, equality test and print are sufficient. A delimiter that only closes the input literal, or a short-circuit that never fires for this trace, adds no needed fact. The benchmark tokenizer counts 291 tokens in this excerpt.

## Current token measurement

Task A: **510 tokens**. Task B: **291 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
