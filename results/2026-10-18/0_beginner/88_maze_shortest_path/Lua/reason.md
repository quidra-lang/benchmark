# Task B selection: 88_maze_shortest_path / Lua

## Common answer requirements

Connect goal discovery and one-time parent assignment to reconstruction and marked-maze output; establish exactly route cells, moves=route cells minus one, and preservation of S/G.

## Answer and source dependencies

On first discovery of an unvisited nonwall neighbor, the search records its current predecessor and queues the neighbor. That includes the goal. Some implementations stop when the goal is dequeued, some stop after discovering it, and others finish the BFS; the recorded parent route is retained. Starting at goal and repeatedly replacing the current cell by its parent follows the discovery tree backward until start. Exactly one link is followed per move, so a route containing k cells has k-1 moves. The loop excludes start; a dot-only replacement or explicit goal exclusion also preserves G. Only intermediate passage cells are changed to asterisks, or marked in a separate path array and substituted at rendering. The final row printer consumes the changed cells/path overlay.



## Scope and dependency evidence checked after independent review

Bind S/G locations before seeding the search, and establish FIFO queue removal/head advancement. Neighbor coordinates are current coordinates plus one of the four unit directions, so assigning parent[neighbor]=current records the previous adjacent cell only on first discovery; parent/seen marking precedes enqueue and cannot be overwritten by a later visit. Search-loop boundaries precede backtracking; backtracking ends before row output. Distance-based variants initialize start distance0. Each goal-to-start parent transition counts one move: a route with k+1 cells has k edges and k-1 intermediate stars. The start is excluded by the termination test; the goal survives through a dot-only marking guard or explicit goal exclusion. Width bindings and the Zig standard writer association establish how the modified rows are rendered. Exact maze literals are unnecessary for this structural relationship.

Source: `main.lua`. Selected original locations: L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L26,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41,L42,L43,L44,L45,L46,L47,L48,L49,L50,L51.

- L13: `for row, line in ipairs(text) do` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    maze[row] = {}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    for column = 1, #line do` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `        local c = line:sub(column, column)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `        maze[row][column] = c` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `        if c == "S" then` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `            start = {row, column}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `        elseif c == "G" then` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `            goal = {row, column}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `        end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L23: `    end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L24: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L26: `local function key(row, column) return row .. "," .. column end` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `local queue, parents, head = {start}, {}, 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `parents[key(table.unpack(start))] = start` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `while head <= #queue do` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `    local cell = queue[head]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `    head = head + 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `    if cell[1] == goal[1] and cell[2] == goal[2] then break end` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `    for _, direction in ipairs({{-1, 0}, {1, 0}, {0, -1}, {0, 1}}) do` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `        local r, c = cell[1] + direction[1], cell[2] + direction[2]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `        local position = key(r, c)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `        if r >= 1 and r <= 9 and c >= 1 and c <= 13 and maze[r][c] ~= "#" and not parents[position] then` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `            parents[position] = cell` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `            queue[#queue + 1] = {r, c}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `        end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L41: `    end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L42: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L43: `local cell, steps = goal, 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `while cell[1] ~= start[1] or cell[2] ~= start[2] do` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `    local r, c = table.unpack(cell)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `    if maze[r][c] == "." then maze[r][c] = "*" end` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L47: `    cell = parents[key(r, c)]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `    steps = steps + 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L50: `io.write(string.format("steps: %d\n", steps))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L51: `for _, row in ipairs(maze) do io.write(table.concat(row), "\n") end` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **667 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 487 tokens. The contiguous original span L13–L51 costs 669 tokens; the complete original source costs 808 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L13: 651 tokens; removes `for row, line in ipairs(text) do` from the dependency chain described above.
- Without L14: 656 tokens; removes `maze[row] = {}` from the dependency chain described above.
- Without L15: 652 tokens; removes `for column = 1, #line do` from the dependency chain described above.
- Without L16: 649 tokens; removes `local c = line:sub(column, column)` from the dependency chain described above.
- Without L17: 653 tokens; removes `maze[row][column] = c` from the dependency chain described above.
- Without L18: 653 tokens; removes `if c == "S" then` from the dependency chain described above.
- Without L19: 653 tokens; removes `start = {row, column}` from the dependency chain described above.
- Without L20: 653 tokens; removes `elseif c == "G" then` from the dependency chain described above.
- Without L21: 653 tokens; removes `goal = {row, column}` from the dependency chain described above.
- Without L22: 663 tokens; removes `end` from the dependency chain described above.
- Without L23: 664 tokens; removes `end` from the dependency chain described above.
- Without L24: 665 tokens; removes `end` from the dependency chain described above.
- Without L26: 639 tokens; removes `local function key(row, column) return row .. "," .. column end` from the dependency chain described above.
- Without L28: 644 tokens; removes `local queue, parents, head = {start}, {}, 1` from the dependency chain described above.
- Without L29: 650 tokens; removes `parents[key(table.unpack(start))] = start` from the dependency chain described above.
- Without L30: 656 tokens; removes `while head <= #queue do` from the dependency chain described above.
- Without L31: 655 tokens; removes `local cell = queue[head]` from the dependency chain described above.
- Without L32: 656 tokens; removes `head = head + 1` from the dependency chain described above.
- Without L33: 632 tokens; removes `if cell[1] == goal[1] and cell[2] == goal[2] then break end` from the dependency chain described above.
- Without L34: 617 tokens; removes `for _, direction in ipairs({{-1, 0}, {1, 0}, {0, -1}, {0, 1}}) do` from the dependency chain described above.
- Without L35: 631 tokens; removes `local r, c = cell[1] + direction[1], cell[2] + direction[2]` from the dependency chain described above.
- Without L36: 651 tokens; removes `local position = key(r, c)` from the dependency chain described above.
- Without L37: 605 tokens; removes `if r >= 1 and r <= 9 and c >= 1 and c <= 13 and maze[r][c] ~= "#" and not parents[position] then` from the dependency chain described above.
- Without L38: 655 tokens; removes `parents[position] = cell` from the dependency chain described above.
- Without L39: 645 tokens; removes `queue[#queue + 1] = {r, c}` from the dependency chain described above.
- Without L40: 663 tokens; removes `end` from the dependency chain described above.
- Without L41: 664 tokens; removes `end` from the dependency chain described above.
- Without L42: 665 tokens; removes `end` from the dependency chain described above.
- Without L43: 653 tokens; removes `local cell, steps = goal, 0` from the dependency chain described above.
- Without L44: 637 tokens; removes `while cell[1] ~= start[1] or cell[2] ~= start[2] do` from the dependency chain described above.
- Without L45: 650 tokens; removes `local r, c = table.unpack(cell)` from the dependency chain described above.
- Without L46: 632 tokens; removes `if maze[r][c] == "." then maze[r][c] = "*" end` from the dependency chain described above.
- Without L47: 651 tokens; removes `cell = parents[key(r, c)]` from the dependency chain described above.
- Without L48: 656 tokens; removes `steps = steps + 1` from the dependency chain described above.
- Without L49: 665 tokens; removes `end` from the dependency chain described above.
- Without L50: 644 tokens; removes `io.write(string.format("steps: %d\n", steps))` from the dependency chain described above.
- Without L51: 631 tokens; removes `for _, row in ipairs(maze) do io.write(table.concat(row), "\n") end` from the dependency chain described above.
