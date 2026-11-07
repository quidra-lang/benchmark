# Task B: 31_pascal_triangle / Julia

Row 0 begins with the single value 1. The next-row construction supplies two endpoint ones and no interior term when the preceding row has length one, so row 1 is [1,1]. It never reads a nonexistent preceding neighbor: empty interior ranges/slices or explicit zero padding cover the boundary.

vcat(1,row[1:end-1]+row[2:end],1) has two empty slices for a singleton row and supplies both endpoints explicitly.

Evidence is from `main.jl`, L2,L5.

- L2: `row = [1]`
- L5: `row = vcat(1, row[1:(end-1)] .+ row[2:end], 1)`

Minimization: Only the initial row value and its one next-row construction are necessary; loop bounds and later row output do not affect this local boundary behavior. The selected complete original lines, in source order, cost 44 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 71, and the complete source costs 85. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
