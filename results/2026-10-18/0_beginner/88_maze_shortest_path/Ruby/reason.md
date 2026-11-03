# Task B selection: 88_maze_shortest_path / Ruby

## Common answer requirements

Connect goal discovery and one-time parent assignment to reconstruction and marked-maze output; establish exactly route cells, moves=route cells minus one, and preservation of S/G.

## Answer and source dependencies

On first discovery of an unvisited nonwall neighbor, the search records its current predecessor and queues the neighbor. That includes the goal. Some implementations stop when the goal is dequeued, some stop after discovering it, and others finish the BFS; the recorded parent route is retained. Starting at goal and repeatedly replacing the current cell by its parent follows the discovery tree backward until start. Exactly one link is followed per move, so a route containing k cells has k-1 moves. The loop excludes start; a dot-only replacement or explicit goal exclusion also preserves G. Only intermediate passage cells are changed to asterisks, or marked in a separate path array and substituted at rendering. The final row printer consumes the changed cells/path overlay.



## Scope and dependency evidence checked after independent review

Bind S/G locations before seeding the search, and establish FIFO queue removal/head advancement. Neighbor coordinates are current coordinates plus one of the four unit directions, so assigning parent[neighbor]=current records the previous adjacent cell only on first discovery; parent/seen marking precedes enqueue and cannot be overwritten by a later visit. Search-loop boundaries precede backtracking; backtracking ends before row output. Distance-based variants initialize start distance0. Each goal-to-start parent transition counts one move: a route with k+1 cells has k edges and k-1 intermediate stars. The start is excluded by the termination test; the goal survives through a dot-only marking guard or explicit goal exclusion. Width bindings and the Zig standard writer association establish how the modified rows are rendered. Exact maze literals are unnecessary for this structural relationship.

Source: `main.rb`. Selected original locations: L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33.

- L5: `height, width = rows.length, rows[0].length` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `maze = rows.join.chars` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `start, goal = maze.index('S'), maze.index('G')` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `parent = {start => start}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `queue = [start]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `until queue.empty?` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `  cell = queue.shift` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `  break if cell == goal` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `  row, column = cell.divmod(width)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `  [[-1, 0], [1, 0], [0, -1], [0, 1]].each do |dr, dc|` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    r, c = row + dr, column + dc` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `    if r.between?(0, height - 1) && c.between?(0, width - 1)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `      neighbor = r * width + c` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `      if maze[neighbor] != '#' && !parent.key?(neighbor)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `        parent[neighbor] = cell` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `        queue << neighbor` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `      end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L22: `    end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L23: `  end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L24: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L25: `steps = 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `cell = goal` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `until cell == start` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `  steps += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `  maze[cell] = '*' if maze[cell] == '.'` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `  cell = parent[cell]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L32: `puts "steps: #{steps}"` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `maze.each_slice(width) { |line| puts line.join }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **389 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 215 tokens. The contiguous original span L5–L33 costs 389 tokens; the complete original source costs 497 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L5: 371 tokens; removes `height, width = rows.length, rows[0].length` from the dependency chain described above.
- Without L6: 379 tokens; removes `maze = rows.join.chars` from the dependency chain described above.
- Without L7: 363 tokens; removes `start, goal = maze.index('S'), maze.index('G')` from the dependency chain described above.
- Without L8: 377 tokens; removes `parent = {start => start}` from the dependency chain described above.
- Without L9: 381 tokens; removes `queue = [start]` from the dependency chain described above.
- Without L10: 382 tokens; removes `until queue.empty?` from the dependency chain described above.
- Without L11: 380 tokens; removes `cell = queue.shift` from the dependency chain described above.
- Without L12: 378 tokens; removes `break if cell == goal` from the dependency chain described above.
- Without L13: 374 tokens; removes `row, column = cell.divmod(width)` from the dependency chain described above.
- Without L14: 344 tokens; removes `[[-1, 0], [1, 0], [0, -1], [0, 1]].each do |dr, dc|` from the dependency chain described above.
- Without L15: 368 tokens; removes `r, c = row + dr, column + dc` from the dependency chain described above.
- Without L16: 354 tokens; removes `if r.between?(0, height - 1) && c.between?(0, width - 1)` from the dependency chain described above.
- Without L17: 373 tokens; removes `neighbor = r * width + c` from the dependency chain described above.
- Without L18: 363 tokens; removes `if maze[neighbor] != '#' && !parent.key?(neighbor)` from the dependency chain described above.
- Without L19: 378 tokens; removes `parent[neighbor] = cell` from the dependency chain described above.
- Without L20: 381 tokens; removes `queue << neighbor` from the dependency chain described above.
- Without L21: 385 tokens; removes `end` from the dependency chain described above.
- Without L22: 386 tokens; removes `end` from the dependency chain described above.
- Without L23: 386 tokens; removes `end` from the dependency chain described above.
- Without L24: 387 tokens; removes `end` from the dependency chain described above.
- Without L25: 383 tokens; removes `steps = 0` from the dependency chain described above.
- Without L26: 383 tokens; removes `cell = goal` from the dependency chain described above.
- Without L27: 381 tokens; removes `until cell == start` from the dependency chain described above.
- Without L28: 382 tokens; removes `steps += 1` from the dependency chain described above.
- Without L29: 364 tokens; removes `maze[cell] = '*' if maze[cell] == '.'` from the dependency chain described above.
- Without L30: 379 tokens; removes `cell = parent[cell]` from the dependency chain described above.
- Without L31: 387 tokens; removes `end` from the dependency chain described above.
- Without L32: 377 tokens; removes `puts "steps: #{steps}"` from the dependency chain described above.
- Without L33: 366 tokens; removes `maze.each_slice(width) { |line| puts line.join }` from the dependency chain described above.
