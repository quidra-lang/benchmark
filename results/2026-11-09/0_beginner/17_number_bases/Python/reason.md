# Task B selection: 17_number_bases / Python

## Answer requirements

Suppose hexadecimal digits 10 through 15 must use lowercase a through f, while the decimal, binary and octal fields remain unchanged. Explain how the hexadecimal conversion or digit-selection stage connects to the common output construction and where the case change belongs. Use 43981 to derive the affected hexadecimal field, and account for zero, prefixes and leading zeros without changing those rules.

## Answer and source evidence

The hexadecimal member/specifier currently selects uppercase digits. Select the lowercase hexadecimal presentation at that same site; the common output keeps its decimal, binary and octal fields unchanged. 43981 is hexadecimal abcd, without a prefix or leading zeros. Zero remains 0 because case affects only digits A..F, not numeric spelling rules.

Change the hexadecimal `X` presentation to `x`; integer formatting supplies the existing zero and no-prefix behavior.

Selected `main.py` lines: 2. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
