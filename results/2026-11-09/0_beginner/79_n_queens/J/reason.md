# Task B: 79_n_queens / J

Reverse the per-row candidate column traversal while retaining the same empty board state, column/diagonal rejection and full recursion/restoration. Descending traversal makes the first size-eight solution `[7,3,0,2,5,1,6,4]` in zero-based columns, the horizontal reflection of the ascending first solution. Retain its independent first-solution snapshot before later branches overwrite working positions, then render rows at those columns. Exhaustive counts remain N=4:2,5:10,6:4,7:40,8:92: candidate order changes discovery order, not which placements are examined.

Reverse i.n in the recursive column loop. Branch position prefixes are value arguments; later alternatives overwrite their own current position, while first retains a completed value.

Evidence is from `main.ijs`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L21,L22,L23,L24,L25,L26.

- L1: `queens =: 3 : 0`
- L2: `'n row positions first' =. y`
- L3: `if. row=n do.`
- L4: `if. (n=8)*.0=#first do. first =. positions end.`
- L5: `(1;first) return.`
- L6: `end.`
- L7: `count =. 0`
- L8: `for_column. i.n do.`
- L9: `differences =. (row{.positions)-column`
- L10: `diagonals =. row-i.row`
- L11: `valid =. -. +./ (differences=0) +. (|differences)=diagonals`
- L12: `if. valid do.`
- L13: `positions =. column row}positions`
- L14: `'found first' =. queens n;(row+1);positions;first`
- L15: `count =. count+found`
- L16: `end.`
- L17: `end.`
- L18: `count;first`
- L19: `)`
- L21: `first =. i.0`
- L22: `for_n. 4+i.5 do.`
- L23: `'count first' =. queens n;0;(n$_1);first`
- L24: `smoutput 'N=',(":n),': ',(":count),' solutions'`
- L25: `end.`
- L26: `for_column. first do. smoutput (column$'.'),'Q',(7-column)$'.' end.`

Minimization: The recursive enumerator, candidate validity, working-state restoration/overwrite, first snapshot, requested sizes and board rendering are needed for this complete ordering change. No unrelated source is selected. The selected complete original lines, in source order, cost 317 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 327, and the complete source costs 334. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
