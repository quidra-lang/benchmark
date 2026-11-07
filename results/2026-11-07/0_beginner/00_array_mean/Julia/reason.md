# Task B: 00_array_mean / Julia

The unformatted mean remains a numeric value. The formatting expression rounds its display to two digits after the decimal point, including a trailing zero when necessary; the line writer supplies the newline. The numeric-to-text operation does not replace the original numeric mean. No list separator or trailing space is requested.

@printf("%.2f\n", mean) combines fixed-point conversion and newline emission. Its single value operand introduces no separator.

Evidence is from `main.jl`, L4,L5.

- L4: `mean = sum(numbers) / length(numbers)`
- L5: `@printf("%.2f\n", mean)`

Minimization: The numeric mean expression and its sole formatting/output statement suffice. The input literal is unnecessary because the question asks how a supplied mean is rendered, not its numerical derivation. The selected complete original lines, in source order, cost 31 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 31, and the complete source costs 69. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
