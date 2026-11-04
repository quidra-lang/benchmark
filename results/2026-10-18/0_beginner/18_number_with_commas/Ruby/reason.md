# Task B selection: 18_number_with_commas / Ruby

For the input −456789 supplied in the question, the three-digit groups from the right are 456 and 789; the output line is `-456,789`. The minus is outside the grouping and there is no comma between it and the first digit.

The regexp locates a position followed by whole digit triples, and its non-word-boundary test excludes the boundary between the minus and the first digit. The sign remains in the original decimal string.

Complete main.rb lines: 2. The literal collection and its traversal only deliver the input scalar that the question already provides. The selected formatter or grouping loop and output supply the algorithm and output evidence. The benchmark tokenizer counts 40 tokens in this excerpt.
