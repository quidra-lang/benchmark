# Task B selection: 18_number_with_commas / Swift

For the input −456789 supplied in the question, the three-digit groups from the right are 456 and 789; the output line is `-456,789`. The minus is outside the grouping and there is no comma between it and the first digit.

Foundation NumberFormatter with the en_US_POSIX decimal style uses commas for three-digit grouping and a leading negative sign outside the magnitude. The input is an exact integer and needs no fractional-place override.

Complete main.swift lines: 3, 4, 5, 8. The literal collection and its traversal only deliver the input scalar that the question already provides. The selected formatter or grouping loop and output supply the algorithm and output evidence. The benchmark tokenizer counts 63 tokens in this excerpt.
