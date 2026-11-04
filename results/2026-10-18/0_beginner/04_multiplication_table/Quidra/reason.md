# Task B selection: 04_multiplication_table / Quidra

## Common answer requirements

Identify the row and column limits, the product field width, and how twelve separator-free fields still become one newline-terminated row.

## Source evidence

The two inclusive loops cover 1 through 9 today. Change both upper bounds to 12 and the integer formatting width from 3 to 4. Plain `print` emits each field without a newline. The argumentless line-output call sits after the inner loop, so leave it in place to terminate each row.

## Minimization

Omitting the final call would hide the row boundary. These four lines are the complete loop and output sequence. Selected complete lines of `main.qui`: 1, 2, 3, 4.
