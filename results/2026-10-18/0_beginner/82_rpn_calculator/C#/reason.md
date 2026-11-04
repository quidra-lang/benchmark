# Task B selection — 82_rpn_calculator / C#

The selected input lines identify expressions 2 and 3. Token recognition accepts only the exact operator tokens, so -17 and -3 are parsed as numbers, while a standalone minus is subtraction. The last stack item is the right operand and the next is the left. Signed int division truncates toward zero. The successive operation results of expression 2 are -3, -12, and 9. In expression 3 the addition leaves only 3 on the stack; the following * hits the fewer-than-two guard and exits the token loop or evaluation function before the trailing token 3. Later expression literals and result presentation provide no trace evidence.

Selected complete source lines: 7, 10, 11, 12, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40.

With the benchmark tokenizer, this selection measures 356 tokens; the previous selection measured 394. The full source is 670 tokens.
