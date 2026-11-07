# Task B selection: 23_palindrome_check / Rust

For the source phrase `Step on no pets.`, the spaces and period are removed and the leading S is lowered, yielding `steponnopets`. The reverse or mirrored pairs match. The program prints the original phrase with the result: `Step on no pets. -> yes`.

The loop binds the original phrase. Byte filtering and ASCII lowercase mapping collect a separate vector; the equality compares its forward and reversed iterators. The print still reads the original phrase.

Complete main.rs lines: 2, 7, 10, 11, 12, 13, 14, 15, 16. The original string binding, normalization, equality test and print are sufficient. A delimiter that only closes the input literal, or a short-circuit that never fires for this trace, adds no needed fact. The benchmark tokenizer counts 169 tokens in this excerpt.

## Current token measurement

Task A: **252 tokens**. Task B: **162 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
