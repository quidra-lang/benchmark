# Task B selection: 24_word_stats / C

Choose the last sentence occurrence independently for each extreme length. Leave the sentence, count, average, and output structure alone.

strtok yields words in sentence order. len is strlen(w); longest and shortest are independently replaced only on strict improvements. Include equality in each comparison; the first-candidate checks still work.

Complete main.c lines: 8, 9, 12, 13, 14, 15. A comparison against an undefined length or an unexplained scan order would omit a tie-selection dependency. Initialization that remains guarded and the unaffected count/average formatting are outside the edit. The benchmark tokenizer counts 125 tokens in this excerpt.
