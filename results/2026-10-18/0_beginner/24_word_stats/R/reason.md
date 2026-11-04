# Task B selection: 24_word_stats / R

Choose the last sentence occurrence independently for each extreme length. Leave the sentence, count, average, and output structure alone.

nchar produces word lengths in the same order as words. Select the last index whose length equals the maximum and the last index whose length equals the minimum rather than using which.max and which.min, which choose the first.

Complete main.R lines: 2, 5. A comparison against an undefined length or an unexplained scan order would omit a tie-selection dependency. Initialization that remains guarded and the unaffected count/average formatting are outside the edit. The benchmark tokenizer counts 43 tokens in this excerpt.
