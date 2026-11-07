# Task B selection: 18_number_with_commas / Go

For the input −456789 supplied in the question, the three-digit groups from the right are 456 and 789; the output line is `-456,789`. The minus is outside the grouping and there is no comma between it and the first digit.

Print the minus for negative input, negate it, then convert the magnitude to base-ten digits. The positive-index guard and remaining digit count insert a comma only before a later three-digit group.

Complete main.go lines: 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21. The literal collection and its traversal only deliver the input scalar that the question already provides. The selected formatter or grouping loop and output supply the algorithm and output evidence. The benchmark tokenizer counts 149 tokens in this excerpt.

## Current token measurement

Task A: **246 tokens**. Task B: **148 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
