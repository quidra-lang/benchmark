# Task B: 68_tic_tac_toe_winner / J

The winner test requires a nonempty first mark and equality of all three values in the selected row/column/diagonal. Its line values do not give a writable alias through which this check changes original board cells. No mutation is performed by the equality test, and the next line check still obtains its intended values from the unchanged board.

Indices select a value array from the board for each line; the check reads that value and does not amend board. Rebinding a local line cannot overwrite original cells.

Evidence is from `main.ijs`, L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13.

- L3: `lines =. 8 3$0 1 2 3 4 5 6 7 8 0 3 6 1 4 7 2 5 8 0 4 8 2 4 6`
- L4: `for_i. i.6 do.`
- L5: `board =. >i{boards`
- L6: `result =. 'draw'`
- L7: `if. '.'e.board do. result =. 'in progress' end.`
- L8: `for_line. lines do.`
- L9: `marks =. line{board`
- L10: `if. ('.'~:{.marks)*.*./marks={.marks do.`
- L11: `result =. ({.marks),' wins' break.`
- L12: `end.`
- L13: `end.`

Minimization: Line construction/selection and the complete winner guard are necessary. Actual game output and unrelated board literals add nothing about line storage or aliasing. The selected complete original lines, in source order, cost 178 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 178, and the complete source costs 269. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
