# Task B selection — 01_sum_max_min / Quidra

The array contains −23 once and 5 twice. `sum()` visits every element, so −23 reduces the sum from 115 to 92 and the two occurrences of 5 contribute 10. `min()` compares element values and reports −23. A duplicate contributes another term to the sum but cannot change the minimum value.

The Math import identifies the reduction API, the array supplies the elements, and the output line shows which results are printed. These are the three selected complete lines of `main.qui`.

The one-argument and receiver extrema follow the Math `develop` specification. Implementation of the new names is pending.

Measurement: Task A 91; Task B 90. Tokenizer: metric/tokenizer.py, unchanged.
