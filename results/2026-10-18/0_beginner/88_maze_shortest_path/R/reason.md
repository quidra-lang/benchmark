# Task B selection: 88_maze_shortest_path / R

## Common answer requirements

Connect goal discovery and one-time parent assignment to reconstruction and marked-maze output; establish exactly route cells, moves=route cells minus one, and preservation of S/G.

## Answer and source dependencies

On first discovery of an unvisited nonwall neighbor, the search records its current predecessor and queues the neighbor. That includes the goal. Some implementations stop when the goal is dequeued, some stop after discovering it, and others finish the BFS; the recorded parent route is retained. Starting at goal and repeatedly replacing the current cell by its parent follows the discovery tree backward until start. Exactly one link is followed per move, so a route containing k cells has k-1 moves. The loop excludes start; a dot-only replacement or explicit goal exclusion also preserves G. Only intermediate passage cells are changed to asterisks, or marked in a separate path array and substituted at rendering. The final row printer consumes the changed cells/path overlay.



## Scope and dependency evidence checked after independent review

Bind S/G locations before seeding the search, and establish FIFO queue removal/head advancement. Neighbor coordinates are current coordinates plus one of the four unit directions, so assigning parent[neighbor]=current records the previous adjacent cell only on first discovery; parent/seen marking precedes enqueue and cannot be overwritten by a later visit. Search-loop boundaries precede backtracking; backtracking ends before row output. Distance-based variants initialize start distance0. Each goal-to-start parent transition counts one move: a route with k+1 cells has k edges and k-1 intermediate stars. The start is excluded by the termination test; the goal survives through a dot-only marking guard or explicit goal exclusion. Width bindings and the Zig standard writer association establish how the modified rows are rendered. Exact maze literals are unnecessary for this structural relationship.

Source: `main.R`. Selected original locations: L13,L14,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41,L42,L43,L44,L45,L46.

- L13: `start <- which(maze == "S", arr.ind = TRUE)[1, ]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `goal <- which(maze == "G", arr.ind = TRUE)[1, ]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `seen <- matrix(FALSE, 9, 13)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `seen[start[1], start[2]] <- TRUE` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `queue <- list(start)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `head_index <- 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `while (head_index <= length(queue)) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `  cell <- queue[[head_index]]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `  head_index <- head_index + 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `  if (all(cell == goal)) break` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `  for (direction in list(c(-1, 0), c(1, 0), c(0, -1), c(0, 1))) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `    next_cell <- cell + direction` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `    r <- next_cell[1]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `    c_value <- next_cell[2]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `    if (r >= 1 && r <= 9 && c_value >= 1 && c_value <= 13 && maze[r, c_value] != "#" && !seen[r, c_value]) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `      seen[r, c_value] <- TRUE` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `      parent_row[r, c_value] <- cell[1]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `      parent_column[r, c_value] <- cell[2]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `      queue[[length(queue) + 1]] <- next_cell` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L34: `  }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L35: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L36: `cell <- goal` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `steps <- 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `while (!all(cell == start)) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `  r <- cell[1]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `  c_value <- cell[2]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `  if (maze[r, c_value] == ".") maze[r, c_value] <- "*"` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `  cell <- c(parent_row[r, c_value], parent_column[r, c_value])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L43: `  steps <- steps + 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L45: `cat(sprintf("steps: %d\n", steps))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `for (r in 1:9) cat(paste(maze[r, ], collapse = ""), "\n", sep = "")` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **616 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 516 tokens. The contiguous original span L13–L46 costs 641 tokens; the complete original source costs 785 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L13: 587 tokens; removes `start <- which(maze == "S", arr.ind = TRUE)[1, ]` from the dependency chain described above.
- Without L14: 587 tokens; removes `goal <- which(maze == "G", arr.ind = TRUE)[1, ]` from the dependency chain described above.
- Without L16: 600 tokens; removes `seen <- matrix(FALSE, 9, 13)` from the dependency chain described above.
- Without L17: 599 tokens; removes `seen[start[1], start[2]] <- TRUE` from the dependency chain described above.
- Without L18: 607 tokens; removes `queue <- list(start)` from the dependency chain described above.
- Without L19: 608 tokens; removes `head_index <- 1` from the dependency chain described above.
- Without L20: 599 tokens; removes `while (head_index <= length(queue)) {` from the dependency chain described above.
- Without L21: 604 tokens; removes `cell <- queue[[head_index]]` from the dependency chain described above.
- Without L22: 601 tokens; removes `head_index <- head_index + 1` from the dependency chain described above.
- Without L23: 600 tokens; removes `if (all(cell == goal)) break` from the dependency chain described above.
- Without L24: 565 tokens; removes `for (direction in list(c(-1, 0), c(1, 0), c(0, -1), c(0, 1))) {` from the dependency chain described above.
- Without L25: 603 tokens; removes `next_cell <- cell + direction` from the dependency chain described above.
- Without L26: 604 tokens; removes `r <- next_cell[1]` from the dependency chain described above.
- Without L27: 602 tokens; removes `c_value <- next_cell[2]` from the dependency chain described above.
- Without L28: 543 tokens; removes `if (r >= 1 && r <= 9 && c_value >= 1 && c_value <= 13 && maze[r, c_value] != "#" && !seen[r, c_value]) {` from the dependency chain described above.
- Without L29: 600 tokens; removes `seen[r, c_value] <- TRUE` from the dependency chain described above.
- Without L30: 595 tokens; removes `parent_row[r, c_value] <- cell[1]` from the dependency chain described above.
- Without L31: 595 tokens; removes `parent_column[r, c_value] <- cell[2]` from the dependency chain described above.
- Without L32: 596 tokens; removes `queue[[length(queue) + 1]] <- next_cell` from the dependency chain described above.
- Without L33: 613 tokens; removes `}` from the dependency chain described above.
- Without L34: 613 tokens; removes `}` from the dependency chain described above.
- Without L35: 614 tokens; removes `}` from the dependency chain described above.
- Without L36: 610 tokens; removes `cell <- goal` from the dependency chain described above.
- Without L37: 610 tokens; removes `steps <- 0` from the dependency chain described above.
- Without L38: 600 tokens; removes `while (!all(cell == start)) {` from the dependency chain described above.
- Without L39: 606 tokens; removes `r <- cell[1]` from the dependency chain described above.
- Without L40: 604 tokens; removes `c_value <- cell[2]` from the dependency chain described above.
- Without L41: 579 tokens; removes `if (maze[r, c_value] == ".") maze[r, c_value] <- "*"` from the dependency chain described above.
- Without L42: 583 tokens; removes `cell <- c(parent_row[r, c_value], parent_column[r, c_value])` from the dependency chain described above.
- Without L43: 605 tokens; removes `steps <- steps + 1` from the dependency chain described above.
- Without L44: 614 tokens; removes `}` from the dependency chain described above.
- Without L45: 597 tokens; removes `cat(sprintf("steps: %d\n", steps))` from the dependency chain described above.
- Without L46: 569 tokens; removes `for (r in 1:9) cat(paste(maze[r, ], collapse = ""), "\n", sep = "")` from the dependency chain described above.
