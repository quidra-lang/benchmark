# Task B selection: 18_number_with_commas / Rust

For the input −456789 supplied in the question, the three-digit groups from the right are 456 and 789; the output line is `-456,789`. The minus is outside the grouping and there is no comma between it and the first digit.

abs supplies just the digits, while a negative input produces a separate leading minus. The positive index and divisibility test control commas before later groups, and println ends the line.

Complete main.rs lines: 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13. The literal collection and its traversal only deliver the input scalar that the question already provides. The selected formatter or grouping loop and output supply the algorithm and output evidence. The benchmark tokenizer counts 155 tokens in this excerpt.
