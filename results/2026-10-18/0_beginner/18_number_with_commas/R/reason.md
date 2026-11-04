# Task B selection: 18_number_with_commas / R

For the input −456789 supplied in the question, the three-digit groups from the right are 456 and 789; the output line is `-456,789`. The minus is outside the grouping and there is no comma between it and the first digit.

The big.mark argument requests comma groups in ordinary, non-scientific notation; trim removes padding. The minus precedes the grouped digits, and cat appends the explicit newline without a separating space.

Complete main.R lines: 2. The literal collection and its traversal only deliver the input scalar that the question already provides. The selected formatter or grouping loop and output supply the algorithm and output evidence. The benchmark tokenizer counts 48 tokens in this excerpt.
