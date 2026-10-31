# Task B selection: 88_maze_shortest_path / Julia

## Common answer requirements

Connect goal discovery and one-time parent assignment to reconstruction and marked-maze output; establish exactly route cells, moves=route cells minus one, and preservation of S/G.

## Answer and source dependencies

On first discovery of an unvisited nonwall neighbor, the search records its current predecessor and queues the neighbor. That includes the goal. Some implementations stop when the goal is dequeued, some stop after discovering it, and others finish the BFS; the recorded parent route is retained. Starting at goal and repeatedly replacing the current cell by its parent follows the discovery tree backward until start. Exactly one link is followed per move, so a route containing k cells has k-1 moves. The loop excludes start; a dot-only replacement or explicit goal exclusion also preserves G. Only intermediate passage cells are changed to asterisks, or marked in a separate path array and substituted at rendering. The final row printer consumes the changed cells/path overlay.



## Scope and dependency evidence checked after independent review

Bind S/G locations before seeding the search, and establish FIFO queue removal/head advancement. Neighbor coordinates are current coordinates plus one of the four unit directions, so assigning parent[neighbor]=current records the previous adjacent cell only on first discovery; parent/seen marking precedes enqueue and cannot be overwritten by a later visit. Search-loop boundaries precede backtracking; backtracking ends before row output. Distance-based variants initialize start distance0. Each goal-to-start parent transition counts one move: a route with k+1 cells has k edges and k-1 intermediate stars. The start is excluded by the termination test; the goal survives through a dot-only marking guard or explicit goal exclusion. Width bindings and the Zig standard writer association establish how the modified rows are rendered. Exact maze literals are unnecessary for this structural relationship.

Source: `main.jl`. Selected original locations: L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41,L42,L43,L44,L45.

- L15: `    for row = 1:9, column = 1:13` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `        maze[row][column] == 'S' && (start = (row, column))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `        maze[row][column] == 'G' && (goal = (row, column))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `    end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L19: `    queue = [start]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `    parents = Dict(start=>start)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `    head = 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `    while head <= length(queue)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `        row, column = queue[head]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `        head += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `        (row, column) == goal && break` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `        for (dr, dc) in [(-1, 0), (1, 0), (0, -1), (0, 1)]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `            next = (row+dr, column+dc)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `            r, c = next` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `            if 1 <= r <= 9 && 1 <= c <= 13 && maze[r][c] != '#' && !haskey(parents, next)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `                parents[next] = (row, column)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `                push!(queue, next)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `            end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L33: `        end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L34: `    end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L35: `    cell = goal` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `    steps = 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `    while cell != start` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `        row, column = cell` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `        maze[row][column] == '.' && (maze[row][column] = '*')` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `        cell = parents[cell]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `        steps += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `    end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L43: `    println("steps: ", steps)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `    for row in maze` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `        println(join(row))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **463 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 346 tokens. The contiguous original span L15–L45 costs 463 tokens; the complete original source costs 642 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L15: 442 tokens; removes `for row = 1:9, column = 1:13` from the dependency chain described above.
- Without L16: 432 tokens; removes `maze[row][column] == 'S' && (start = (row, column))` from the dependency chain described above.
- Without L17: 432 tokens; removes `maze[row][column] == 'G' && (goal = (row, column))` from the dependency chain described above.
- Without L18: 460 tokens; removes `end` from the dependency chain described above.
- Without L19: 454 tokens; removes `queue = [start]` from the dependency chain described above.
- Without L20: 451 tokens; removes `parents = Dict(start=>start)` from the dependency chain described above.
- Without L21: 456 tokens; removes `head = 1` from the dependency chain described above.
- Without L22: 451 tokens; removes `while head <= length(queue)` from the dependency chain described above.
- Without L23: 449 tokens; removes `row, column = queue[head]` from the dependency chain described above.
- Without L24: 455 tokens; removes `head += 1` from the dependency chain described above.
- Without L25: 446 tokens; removes `(row, column) == goal && break` from the dependency chain described above.
- Without L26: 415 tokens; removes `for (dr, dc) in [(-1, 0), (1, 0), (0, -1), (0, 1)]` from the dependency chain described above.
- Without L27: 445 tokens; removes `next = (row+dr, column+dc)` from the dependency chain described above.
- Without L28: 451 tokens; removes `r, c = next` from the dependency chain described above.
- Without L29: 408 tokens; removes `if 1 <= r <= 9 && 1 <= c <= 13 && maze[r][c] != '#' && !haskey(parents, next)` from the dependency chain described above.
- Without L30: 445 tokens; removes `parents[next] = (row, column)` from the dependency chain described above.
- Without L31: 450 tokens; removes `push!(queue, next)` from the dependency chain described above.
- Without L32: 458 tokens; removes `end` from the dependency chain described above.
- Without L33: 459 tokens; removes `end` from the dependency chain described above.
- Without L34: 460 tokens; removes `end` from the dependency chain described above.
- Without L35: 456 tokens; removes `cell = goal` from the dependency chain described above.
- Without L36: 456 tokens; removes `steps = 0` from the dependency chain described above.
- Without L37: 454 tokens; removes `while cell != start` from the dependency chain described above.
- Without L38: 452 tokens; removes `row, column = cell` from the dependency chain described above.
- Without L39: 429 tokens; removes `maze[row][column] == '.' && (maze[row][column] = '*')` from the dependency chain described above.
- Without L40: 452 tokens; removes `cell = parents[cell]` from the dependency chain described above.
- Without L41: 455 tokens; removes `steps += 1` from the dependency chain described above.
- Without L42: 460 tokens; removes `end` from the dependency chain described above.
- Without L43: 450 tokens; removes `println("steps: ", steps)` from the dependency chain described above.
- Without L44: 454 tokens; removes `for row in maze` from the dependency chain described above.
- Without L45: 453 tokens; removes `println(join(row))` from the dependency chain described above.
