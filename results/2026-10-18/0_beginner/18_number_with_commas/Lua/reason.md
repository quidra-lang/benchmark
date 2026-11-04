# Task B selection: 18_number_with_commas / Lua

For the input −456789 supplied in the question, the three-digit groups from the right are 456 and 789; the output line is `-456,789`. The minus is outside the grouping and there is no comma between it and the first digit.

The absolute value removes the sign before digit reversal and replacement. Grouped reversed triples turn into right-aligned groups after reversing again; stripping the leading comma prevents an extra separator before the first group. The conditional sign is written ahead of them.

Complete main.lua lines: 2, 3, 4. The literal collection and its traversal only deliver the input scalar that the question already provides. The selected formatter or grouping loop and output supply the algorithm and output evidence. The benchmark tokenizer counts 97 tokens in this excerpt.
