# Task B selection: 18_number_with_commas / Dart

The absolute value supplies just the digits, while the minus is written separately. The indexed digit loop inserts a comma when a positive index leaves a multiple of three digits. writeln ends the buffered line, and stdout.write sends it to output. The supplied input −456789 prints as `-456,789`, with the two groups 456 and 789 and the sign outside them.

Complete main.dart lines: 6, 7, 8, 9, 10, 11, 12, 14. The other source values, their traversal, and buffer allocation add no information about the named scalar or grouping. Keeping the buffer constructor would add 13 tokens. The benchmark tokenizer counts 143 tokens in this excerpt.

## Current token measurement

Task A: **235 tokens**. Task B: **140 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
