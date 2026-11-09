# Task B: 31_pascal_triangle / J

Row 0 begins with the single value 1. The next-row construction supplies two endpoint ones and no interior term when the preceding row has length one, so row 1 is [1,1]. It never reads a nonexistent preceding neighbor: empty interior ranges/slices or explicit zero padding cover the boundary.

The update adds (0,row) to (row,0): [0,1]+[1,0]=[1,1], with no out-of-bounds read.

Evidence is from `main.ijs`, L2,L5.

- L2: `row =. ,1`
- L5: `row =. (0,row)+(row,0)`

Minimization: Only the initial row value and its one next-row construction are necessary; loop bounds and later row output do not affect this local boundary behavior. The selected complete original lines, in source order, cost 25 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 44, and the complete source costs 64. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
