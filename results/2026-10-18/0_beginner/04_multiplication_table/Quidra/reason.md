# Task B selection: 04_multiplication_table / Quidra

## Answer requirements

Locate both table dimensions and the product-field width; explain how the new bounds and width produce the requested rows.

## Evidence and answer

The inclusive row and column loops each change their endpoint from 9 to 12. The product is already emitted in the inner loop; int=3 sets the interpolation width with left spaces by default, and only the width changes to 4. The existing outer-row newline needs no edit: each last field ends with its product digits, so the existing newline follows without trailing spaces.

## Minimization

Selected complete lines of `main.qui`: 1, 2, 3. The excerpt preserves their text, indentation and order.

The newline-only line is an unchanged action and adds no edit site. The alternative using the range headers alone would not identify the field-width change. The previous excerpt contained 53 tokens; the selected excerpt contains **46 tokens** using `metric/tokenizer.py`.

Measurement: Task A 51; Task B 46. Tokenizer: metric/tokenizer.py, unchanged.
