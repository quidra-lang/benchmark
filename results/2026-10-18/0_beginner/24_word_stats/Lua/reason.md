# Task B selection: 24_word_stats / Lua

Choose the last sentence occurrence independently for each extreme length. Leave the sentence, count, average, and output structure alone.

ipairs visits words in increasing index order. Widen the two independent length comparisons to include equality, so tied later words replace the current candidates.

Complete main.lua lines: 6, 8, 9. A comparison against an undefined length or an unexplained scan order would omit a tie-selection dependency. Initialization that remains guarded and the unaffected count/average formatting are outside the edit. The benchmark tokenizer counts 58 tokens in this excerpt.
