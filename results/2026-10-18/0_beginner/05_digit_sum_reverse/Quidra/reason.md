# Task B selection for 05_digit_sum_reverse

For 98000, the decimal text has length 5. The selected comprehension maps every ASCII digit code point to its numeric value by subtracting 48, so zeros count toward length and add zero to the sum of 17. Reversing the text and parsing 00089 as an integer gives 89. The output line shows the three labels and the question supplies the input number, so the input list and outer loop are unnecessary.

Selected complete lines in order are 1, 5, 6, 7, 8.

Task A uses 154 tokens. Task B uses 96 tokens.

Measurement: Task A 154; Task B 96. Tokenizer: metric/tokenizer.py, unchanged.

The numeric string conversion gives string, whose codepoints() result is int[]. The comprehension therefore infers an int element binding, and the unchanged subtraction and sum use exact integers.
