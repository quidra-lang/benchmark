# Task B: 55_grid_paths / J

The top-left base state is one path: the empty route already at the start, not a movement from a predecessor. Both counting cases invoke the same routine with different obstacle flags, so the same origin initialization applies. The supplied top-left cell is open, hence obstacle handling does not erase this one.

dp starts zero everywhere, then 1 is written at coordinate (0,0). The obstacle branch could clear a blocked origin, but this grid starts with a dot; both calls share the initializer.

Evidence is from `main.ijs`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L19,L20.

- L1: `paths =: 3 : 0`
- L2: `grid =. > '.......';'..#....';'....#..';'.#.....';'...#.#.';'.......'`
- L3: `dp =. 6 7$0`
- L4: `dp =. 1 (<0 0)}dp`
- L5: `for_r. i.6 do.`
- L6: `for_c. i.7 do.`
- L7: `cell =. <r,c`
- L8: `if. y *. '#'=cell{grid do. dp =. 0 cell}dp`
- L9: `elseif. (r~:0)+.c~:0 do.`
- L19: `smoutput 'without obstacles: ',":paths 0`
- L20: `smoutput 'with obstacles: ',":paths 1`

Minimization: The base/default state, origin-versus-obstacle condition and the two call modes are sufficient. The predecessor recurrence and propagation to the far corner are outside this base-state question. The selected complete original lines, in source order, cost 191 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 293, and the complete source costs 293. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
