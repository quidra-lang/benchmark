# Task B selection — 01_sum_max_min / Quidra

The array contains −23 once and 5 twice. `sum()` visits every element, so −23 reduces the sum from 115 to 92 and the two occurrences of 5 contribute 10. `min()` compares element values and reports −23. A duplicate contributes another term to the sum but cannot change the minimum value.

The array declaration supplies the input elements, and the output line identifies the Core `sum()` and `min()` calls. Both source lines are necessary to trace the reported results for this input.

Measurement: Task A 86; Task B 86. Tokenizer: metric/tokenizer.py, unchanged.
