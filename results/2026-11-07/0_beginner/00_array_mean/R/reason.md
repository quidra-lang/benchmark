# Task B: 00_array_mean / R

The unformatted mean remains a numeric value. The formatting expression rounds its display to two digits after the decimal point, including a trailing zero when necessary; the line writer supplies the newline. The numeric-to-text operation does not replace the original numeric mean. No list separator or trailing space is requested.

sprintf("%.2f", average) supplies the fixed two-decimal text, and cat appends only its explicit newline. The named average is computed with mean(values).

Evidence is from `main.R`, L2,L3.

- L2: `average <- mean(values)`
- L3: `cat(sprintf("%.2f\n", average))`

Minimization: The numeric mean expression and its sole formatting/output statement suffice. The input literal is unnecessary because the question asks how a supplied mean is rendered, not its numerical derivation. The selected complete original lines, in source order, cost 26 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 26, and the complete source costs 60. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
