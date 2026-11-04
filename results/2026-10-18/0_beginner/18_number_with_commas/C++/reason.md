# Task B selection: 18_number_with_commas / C++

For the input −456789 supplied in the question, the three-digit groups from the right are 456 and 789; the output line is `-456,789`. The minus is outside the grouping and there is no comma between it and the first digit.

to_string leaves the minus in text. The start index skips it, prints it separately and starts the loop at the first digit; the first-digit guard prevents a separator immediately after the sign.

Complete main.cpp lines: 7, 8, 9, 10, 11, 12, 13, 14, 15, 16. The literal collection and its traversal only deliver the input scalar that the question already provides. The selected formatter or grouping loop and output supply the algorithm and output evidence. The benchmark tokenizer counts 192 tokens in this excerpt.
