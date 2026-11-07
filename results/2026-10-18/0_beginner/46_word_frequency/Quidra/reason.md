# Task B selection for 46_word_frequency

The passage and ASCII word tokenization show that Dog is normalized to dog before counting. For example, cat and bird both occur three times, so ranked_entries places bird before cat by ascending key on equal counts. The slice retains the first five ranked entries. The final printed totals do not supply ranking evidence.

Selected complete lines in order are 1, 2, 4, 5, 6, 7.

Task A uses 208 tokens. Task B uses 175 tokens.

Measurement: Task A 208; Task B 175. Tokenizer: metric/tokenizer.py, unchanged.

## Current token measurement

Task A: **206 tokens**. Task B: **174 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
