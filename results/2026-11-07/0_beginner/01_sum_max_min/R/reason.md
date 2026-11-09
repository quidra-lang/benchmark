# Task B: 01_sum_max_min / R

The collection contains 5 twice. The reduction consumes both positions independently, so the accumulator includes +5 twice; duplicate values do not collapse. Its implicit traversal ends at the collection length of ten and advances once per element, without an extra element.

In R the positions are 4 and 7, using one-based indices. sum(values) reduces the vector, including repeated values.

Evidence is from `main.R`, L1,L2.

- L1: `values <- c(17, -8, 42, 5, -23, 36, 5, 0, -11, 29)`
- L2: `total <- sum(values)`

Minimization: The literal establishes both occurrence positions and the ten-element bound; the total-producing reduction establishes traversal and accumulation. Max/min calculations and output labels add no evidence about processing either 5. The selected complete original lines, in source order, cost 54 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 54, and the complete source costs 97. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
