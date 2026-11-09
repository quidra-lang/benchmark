# Task B: 77_langtons_ant / J

Keep the current turn from cell color and the current cell flip before deciding movement. Compute proposed coordinates from the resulting direction, then commit both only if they lie within the board; otherwise retain both current coordinates. Replace the modulo wrapping at the move expressions with that bounds/commit step. A proposed upward move from row 0 to row -1 is refused, while the already completed turn and flip remain in effect.

The zero-based 11×11 board uses row/col 0..10. Color-dependent direction change and cell amendment precede the current modulus-wrapped coordinate assignments.

Evidence is from `main.ijs`, L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14.

- L2: `black =. 11 11$0`
- L3: `row =. column =. 5`
- L4: `direction =. 0`
- L5: `steps =. 4 2$_1 0 0 1 1 0 0 _1`
- L6: `for_step. i.300 do.`
- L7: `cell =. <row,column`
- L8: `if. cell{black do. direction =. 4|direction+3`
- L9: `else. direction =. 4|direction+1`
- L10: `end.`
- L11: `black =. (-.cell{black) cell}black`
- L12: `'dr dc' =. direction{steps`
- L13: `row =. 11|row+dr`
- L14: `column =. 11|column+dc`

Minimization: Incoming board/position/direction, color rule, flip, direction offsets and both coordinate updates are necessary for one complete step. Multi-step output is unrelated to boundary commit behavior. The selected complete original lines, in source order, cost 169 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 169, and the complete source costs 240. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
