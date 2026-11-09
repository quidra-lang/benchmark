# Task B: 88_maze_shortest_path / R

Parent writes and reconstruction reads must agree on one predecessor value representation, including the start marker. Keep first-discovery timing and BFS ordering unchanged. If parent values become (row,column) pairs, store the current coordinates at each child discovery, read both coordinates together when stepping backward, and use a consistent self-parent or separate sentinel for the start.

Current predecessor coordinates are split across parent_row and parent_column matrices. Together they represent a pair, but if a uniform pair-valued storage contract is required, combine their writes/reads into one pair collection; reconstruction stops at start before reading its unused zero marker.

Evidence is from `main.R`, L15,L16,L17,L25,L26,L27,L28,L29,L30,L31,L36,L38,L39,L40,L42.

- L15: `parent_row <- parent_column <- matrix(0L, 9, 13)`
- L16: `seen <- matrix(FALSE, 9, 13)`
- L17: `seen[start[1], start[2]] <- TRUE`
- L25: `next_cell <- cell + direction`
- L26: `r <- next_cell[1]`
- L27: `c_value <- next_cell[2]`
- L28: `if (r >= 1 && r <= 9 && c_value >= 1 && c_value <= 13 && maze[r, c_value] != "#" && !seen[r, c_value]) {`
- L29: `seen[r, c_value] <- TRUE`
- L30: `parent_row[r, c_value] <- cell[1]`
- L31: `parent_column[r, c_value] <- cell[2]`
- L36: `cell <- goal`
- L38: `while (!all(cell == start)) {`
- L39: `r <- cell[1]`
- L40: `c_value <- cell[2]`
- L42: `cell <- c(parent_row[r, c_value], parent_column[r, c_value])`

Minimization: The existing parent initialization/start marker, child write and reverse read are necessary to assess representation. Neighbor enumeration and queue operations are not changed and do not need selection. The selected complete original lines, in source order, cost 305 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 504, and the complete source costs 785. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
