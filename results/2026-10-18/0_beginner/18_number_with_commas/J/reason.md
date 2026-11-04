# Task B selection: 18_number_with_commas / J

For the input −456789 supplied in the question, the three-digit groups from the right are 456 and 789; the output line is `-456,789`. The minus is outside the grouping and there is no comma between it and the first digit.

The c0 format of the standard J 8!:2 foreign groups the integer digits using commas and no fractional digits, with the negative sign outside the groups. smoutput prints the formatted row.

Complete main.ijs lines: 3. The literal collection and its traversal only deliver the input scalar that the question already provides. The selected formatter or grouping loop and output supply the algorithm and output evidence. The benchmark tokenizer counts 15 tokens in this excerpt.
