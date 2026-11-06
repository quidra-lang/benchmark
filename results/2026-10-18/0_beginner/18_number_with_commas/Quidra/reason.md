# Task B selection: 18_number_with_commas / Quidra

For the input −456789 supplied in the question, the three-digit groups from the right are 456 and 789; the output line is `-456,789`. The minus is outside the grouping and there is no comma between it and the first digit.

The `:3` grouping suffix (written `{n::3}`) applies to integer digits from the right and preserves the negative sign as a prefix outside the grouping. println emits the formatted line.

Complete main.qui lines: 2. The literal collection and its traversal only deliver the input scalar that the question already provides. The selected formatter or grouping loop and output supply the algorithm and output evidence. The benchmark tokenizer counts 12 tokens in this excerpt.

Measurement: Task A 67; Task B 12. Tokenizer: metric/tokenizer.py, unchanged.
