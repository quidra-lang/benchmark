# Task B: 57_matrix_determinant / J

The one-entry base returns that entry. Each first-row column creates a minor by deleting the first row and that column, recursively evaluates it, multiplies by the corresponding first-row entry and adds/subtracts with alternating signs. For matrix 1 the first term is 2×det[[4,-2],[6,3]]=2×24=48. There is no division or pre-output rounding: all signed terms and the result remain exact integers for these inputs.

J uses zero-based even j for the positive sign and integer array arithmetic throughout this determinant routine.

Evidence is from `main.ijs`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L15.

- L1: `determinant =: 3 : 0`
- L2: `n =. #y`
- L3: `if. n=1 do. (<0 0){y return. end.`
- L4: `total =. 0`
- L5: `for_j. i.n do.`
- L6: `minor =. (j~:i.n) #"1 }.y`
- L7: `term =. (j{0{y)*determinant minor`
- L8: `if. 0=2|j do. total =. total+term`
- L9: `else. total =. total-term`
- L10: `end.`
- L11: `end.`
- L12: `total`
- L15: `matrices =. (3 3$2 _3 1 5 4 _2 _1 6 3);(4 4$3 0 _2 5 1 4 7 _3 _6 2 1 8 9 _5 3 2);(5 5$4 _1 7 0 _3 2 8 _5 6 1 _9 3 2 _4 5 6 0 _7 3 _2 1 _6 4 9 8)`

Minimization: The recursive routine and first-matrix literal are needed for the concrete first term. Other matrices can be omitted on separately written lines; the J literal necessarily shares its complete line with the other matrices. The selected complete original lines, in source order, cost 273 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 285, and the complete source costs 368. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
