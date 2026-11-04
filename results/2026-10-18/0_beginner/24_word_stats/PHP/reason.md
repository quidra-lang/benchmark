# Task B selection: 24_word_stats / PHP

Choose the last sentence occurrence independently for each extreme length. Leave the sentence, count, average, and output structure alone.

array_map produces each word’s strlen at its original index; array_search chooses the first index with the maximum or minimum length. For each target length choose the greatest matching index; use it to index the unchanged words array.

Complete main.php lines: 4, 5, 6. A comparison against an undefined length or an unexplained scan order would omit a tie-selection dependency. Initialization that remains guarded and the unaffected count/average formatting are outside the edit. The benchmark tokenizer counts 75 tokens in this excerpt.
