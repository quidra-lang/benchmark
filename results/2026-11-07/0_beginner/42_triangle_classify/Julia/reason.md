# Task B: 42_triangle_classify / Julia

Sort the three sides first. Split the current a+b<=c invalid branch into a+b<c → `not a triangle`, a+b==c → `degenerate`, and the existing strict-valid else branch. The supplied (3,8,5) sorts to (3,5,8) and reaches equality. Only a+b>c continues into the existing side/angle classification; other boundaries are unchanged.

The sorted tuple binding and if/else separate invalid input from side/angle classification; the equality case must be inserted before the current else.

Evidence is from `main.jl`, L2,L3,L11,L12,L13,L14,L15,L16,L20.

- L2: `for sides in [`
- L3: `(3, 8, 5),`
- L11: `]`
- L12: `a, b, c = sort(collect(sides))`
- L13: `if a+b <= c`
- L14: `result = "not a triangle"`
- L15: `else`
- L16: `side = a == c ? "equilateral" : a == b || b == c ? "isosceles" : "scalene"`
- L20: `end`

Minimization: The supplied equality-case data, sorted-side binding and validity/else boundary suffice. The internals of valid angle classification are not needed beyond locating its existing entry and result join. The selected complete original lines, in source order, cost 127 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 304, and the complete source costs 342. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
