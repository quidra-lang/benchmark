# Task B: 03_circle_area / R

The area field uses the literal label ` area=` immediately followed by fixed-point formatting with precision 3. That conversion always includes three fractional digits, retaining trailing zeros if the numeric area requires them. It affects only displayed text; the area calculation and circumference field do not need to change.

The area portion of the complete sprintf expression is ` area=%.3f` with area as its corresponding argument.

Evidence is from `main.R`, L5.

- L5: `cat(sprintf("r=%d area=%.3f circumference=%.3f\n", radius, area, circumference))`

Minimization: Only the complete line containing the requested area-format expression is selected. Radius iteration and area/circumference arithmetic are outside this expression-level question; adjacent fields occur on that same indivisible source line. The selected complete original lines, in source order, cost 37 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 37, and the complete source costs 127. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
