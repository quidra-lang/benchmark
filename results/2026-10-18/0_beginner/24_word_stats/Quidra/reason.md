# Task B selection: 24_word_stats / Quidra

Choose the last sentence occurrence independently for each extreme length. Leave the sentence, count, average, and output structure alone.

The collection iteration visits words in source order. Include equality in the independent len comparisons, preserving the per-extreme assignments and the stored words.

Complete main.qui lines: 5, 7, 8, 9, 10. A comparison against an undefined length or an unexplained scan order would omit a tie-selection dependency. Initialization that remains guarded and the unaffected count/average formatting are outside the edit. The benchmark tokenizer counts 55 tokens in this excerpt.
