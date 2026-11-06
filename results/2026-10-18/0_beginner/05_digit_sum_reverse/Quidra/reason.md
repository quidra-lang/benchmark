# Task B selection — 05_digit_sum_reverse / Quidra

For 98000, `digits()` yields `[9, 8, 0, 0, 0]`. The three zeros are included in the length of 5 and contribute zero to the sum of 17. Reversing the decimal text yields `00089`, and integer parsing gives 89. The complete line is `98000: digits=5 sum=17 reversed=89`.

The Math import and lines 5–7 of `main.qui` supply the digit decomposition, reversal, and output fields. The question gives the input value, so the fixture and loop header supply no additional evidence.

The digit-decomposition API is specified for Math `develop`. Implementation is pending.

Measurement: Task A 129; Task B 71. Tokenizer: metric/tokenizer.py, unchanged.
