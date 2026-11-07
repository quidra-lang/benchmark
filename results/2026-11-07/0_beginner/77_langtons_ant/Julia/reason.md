# Task B: 77_langtons_ant / Julia

Keep the current turn from cell color and the current cell flip before deciding movement. Compute proposed coordinates from the resulting direction, then commit both only if they lie within the board; otherwise retain both current coordinates. Replace the modulo wrapping at the move expressions with that bounds/commit step. A proposed upward move from row 0 to row -1 is refused, while the already completed turn and flip remain in effect.

The logical ant position is zero-based and board indexing adds 1. Replace mod(row+dr,11)/mod(column+dc,11) after the turn/flip with a joint 0..10 guard.

Evidence is from `main.jl`, L2,L3,L4,L5,L6,L7,L8,L9.

- L2: `board = falses(11, 11)`
- L3: `row, column, direction = 5, 5, 0`
- L4: `directions = [(-1, 0), (0, 1), (1, 0), (0, -1)]`
- L5: `for step = 1:300`
- L6: `direction = mod(direction+(board[row+1, column+1] ? -1 : 1), 4)`
- L7: `board[row+1, column+1] = !board[row+1, column+1]`
- L8: `dr, dc = directions[direction+1]`
- L9: `row, column = mod(row+dr, 11), mod(column+dc, 11)`

Minimization: Incoming board/position/direction, color rule, flip, direction offsets and both coordinate updates are necessary for one complete step. Multi-step output is unrelated to boundary commit behavior. The selected complete original lines, in source order, cost 201 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 201, and the complete source costs 319. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
