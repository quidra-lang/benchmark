# Task B: 00_array_mean / J

The unformatted mean remains a numeric value. The formatting expression rounds its display to two digits after the decimal point, including a trailing zero when necessary; the line writer supplies the newline. The numeric-to-text operation does not replace the original numeric mean. No list separator or trailing space is requested.

The dyadic 8!:2 format specification '2' fixes two decimal places; , flattens the formatted character array before smoutput writes its line.

Evidence is from `main.ijs`, L2,L3.

- L2: `mean =: (+/values) % #values`
- L3: `smoutput , '2' 8!:2 mean`

Minimization: The numeric mean expression and its sole formatting/output statement suffice. The input literal is unnecessary because the question asks how a supplied mean is rendered, not its numerical derivation. The selected complete original lines, in source order, cost 29 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 29, and the complete source costs 54. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
