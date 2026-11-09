# Task B: 88_maze_shortest_path / J

Parent writes and reconstruction reads must agree on one predecessor value representation, including the start marker. Keep first-discovery timing and BFS ordering unchanged. If parent values become (row,column) pairs, store the current coordinates at each child discovery, read both coordinates together when stepping backward, and use a consistent self-parent or separate sentinel for the start.

Current parents are flattened cell numbers, including parent[start]=start, and reconstruction reads/decomposes those numbers. Change the stored value type and both write/read conversions together; a scalar sentinel cannot silently stand in for a required pair.

Evidence is from `main.ijs`, L4,L6,L7,L14,L15,L21,L22,L23,L30,L31,L33.

- L4: `start =. flat i.'S'`
- L6: `parent =. (#flat)$_1`
- L7: `parent =. start start}parent`
- L14: `row =. <.current%13`
- L15: `column =. 13|current`
- L21: `neighbor =. (nr*13)+nc`
- L22: `if. ('#'~:neighbor{flat)*._1=neighbor{parent do.`
- L23: `parent =. current neighbor}parent`
- L30: `current =. goal`
- L31: `while. current~:start do.`
- L33: `current =. current{parent`

Minimization: The existing parent initialization/start marker, child write and reverse read are necessary to assess representation. Neighbor enumeration and queue operations are not changed and do not need selection. The selected complete original lines, in source order, cost 133 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 353, and the complete source costs 508. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
