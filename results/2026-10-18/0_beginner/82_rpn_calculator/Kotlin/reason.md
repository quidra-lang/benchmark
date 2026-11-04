# Task B selection — 82_rpn_calculator / Kotlin

The selected input lines identify expressions 2 and 3. Token recognition accepts only the exact operator tokens, so -17 and -3 are parsed as numbers, while a standalone minus is subtraction. The last stack item is the right operand and the next is the left. Integer division on Int truncates toward zero. The successive operation results of expression 2 are -3, -12, and 9. In expression 3 the addition leaves only 3 on the stack; the following * hits the fewer-than-two guard and exits the token loop or evaluation function before the trailing token 3. Later expression literals and result presentation provide no trace evidence.

Selected complete source lines: 2, 5, 6, 8, 9, 10, 11, 12, 13, 14, 15, 20, 21, 22, 23, 24, 25, 26, 27.

With the benchmark tokenizer, this selection measures 333 tokens; the previous selection measured 370. The full source is 609 tokens.
