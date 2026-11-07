# Task B selection: 18_number_with_commas / Zig

For the input −456789 supplied in the question, the three-digit groups from the right are 456 and 789; the output line is `-456,789`. The minus is outside the grouping and there is no comma between it and the first digit.

@abs supplies just the digits, while a negative input writes a separate leading minus. Only a positive index with a multiple of three digits left triggers a comma; the last write ends the line.

Complete main.zig lines: 9, 10, 11, 12, 13, 14, 15, 16, 17. The literal collection and its traversal only deliver the input scalar that the question already provides. The selected formatter or grouping loop and output supply the algorithm and output evidence. The benchmark tokenizer counts 172 tokens in this excerpt.

## Current token measurement

Task A: **371 tokens**. Task B: **172 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
