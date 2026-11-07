# Task B: 42_triangle_classify / J

Sort the three sides first. Split the current a+b<=c invalid branch into a+b<c → `not a triangle`, a+b==c → `degenerate`, and the existing strict-valid else branch. The supplied (3,8,5) sorts to (3,5,8) and reaches equality. Only a+b>c continues into the existing side/angle classification; other boundaries are unchanged.

The J source sets an invalid default and enters classification only when a+b>c. Preserve that strict-valid branch and add an equality-specific alternative/default override for a+b=c before output.

Evidence is from `main.ijs`, L2,L3,L4,L5,L6,L15.

- L2: `for_original. 8 3$3 8 5 6 6 6 5 8 5 13 5 12 2 9 4 7 4 7 8 6 7 4 9 6 do.`
- L3: `'a b c' =. /:~original`
- L4: `result =. 'not a triangle'`
- L5: `if. (a+b)>c do.`
- L6: `side =. 'scalene'`
- L15: `end.`

Minimization: The supplied equality-case data, sorted-side binding and validity/else boundary suffice. The internals of valid angle classification are not needed beyond locating its existing entry and result join. The selected complete original lines, in source order, cost 116 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 250, and the complete source costs 286. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
