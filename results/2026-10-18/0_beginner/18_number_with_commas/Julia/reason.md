# Task B selection: 18_number_with_commas / Julia

For the input −456789 supplied in the question, the three-digit groups from the right are 456 and 789; the output line is `-456,789`. The minus is outside the grouping and there is no comma between it and the first digit.

The regular-expression lookahead accepts one or more full digit triples up to the end. The lookbehind also requires a digit immediately before the insertion point, excluding the point after the minus.

Complete main.jl lines: 2. The literal collection and its traversal only deliver the input scalar that the question already provides. The selected formatter or grouping loop and output supply the algorithm and output evidence. The benchmark tokenizer counts 42 tokens in this excerpt.
