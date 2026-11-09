# Task B: 31_pascal_triangle / R

Row 0 begins with the single value 1. The next-row construction supplies two endpoint ones and no interior term when the preceding row has length one, so row 1 is [1,1]. It never reads a nonexistent preceding neighbor: empty interior ranges/slices or explicit zero padding cover the boundary.

c(1,head(row,-1)+tail(row,-1),1) has an empty interior for a singleton row and supplies endpoint ones explicitly.

Evidence is from `main.R`, L1,L4.

- L1: `row <- 1`
- L4: `row <- c(1, head(row, -1) + tail(row, -1), 1)`

Minimization: Only the initial row value and its one next-row construction are necessary; loop bounds and later row output do not affect this local boundary behavior. The selected complete original lines, in source order, cost 40 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 87, and the complete source costs 89. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
