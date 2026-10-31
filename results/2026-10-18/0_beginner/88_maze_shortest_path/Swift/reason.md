# Task B selection: 88_maze_shortest_path / Swift

## Common answer requirements

Connect goal discovery and one-time parent assignment to reconstruction and marked-maze output; establish exactly route cells, moves=route cells minus one, and preservation of S/G.

## Answer and source dependencies

On first discovery of an unvisited nonwall neighbor, the search records its current predecessor and queues the neighbor. That includes the goal. Some implementations stop when the goal is dequeued, some stop after discovering it, and others finish the BFS; the recorded parent route is retained. Starting at goal and repeatedly replacing the current cell by its parent follows the discovery tree backward until start. Exactly one link is followed per move, so a route containing k cells has k-1 moves. The loop excludes start; a dot-only replacement or explicit goal exclusion also preserves G. Only intermediate passage cells are changed to asterisks, or marked in a separate path array and substituted at rendering. The final row printer consumes the changed cells/path overlay.



## Scope and dependency evidence checked after independent review

Bind S/G locations before seeding the search, and establish FIFO queue removal/head advancement. Neighbor coordinates are current coordinates plus one of the four unit directions, so assigning parent[neighbor]=current records the previous adjacent cell only on first discovery; parent/seen marking precedes enqueue and cannot be overwritten by a later visit. Search-loop boundaries precede backtracking; backtracking ends before row output. Distance-based variants initialize start distance0. Each goal-to-start parent transition counts one move: a route with k+1 cells has k edges and k-1 intermediate stars. The start is excluded by the termination test; the goal survives through a dot-only marking guard or explicit goal exclusion. Width bindings and the Zig standard writer association establish how the modified rows are rendered. Exact maze literals are unnecessary for this structural relationship.

Source: `main.swift`. Selected original locations: L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41,L42,L43.

- L13: `for r in 0..<9 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    for c in 0..<13 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `        if maze[r][c] == "S" { start = r * 13 + c }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `        if maze[r][c] == "G" { goal = r * 13 + c }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L18: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L19: `var parent = [Int](repeating: -1, count: 117), queue = [start], head = 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `parent[start] = start` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `let dr = [-1, 1, 0, 0], dc = [0, 0, -1, 1]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `while head < queue.count {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `    let cell = queue[head], r = cell / 13, c = cell % 13` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `    head += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `    if cell == goal { break }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `    for d in 0..<4 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `        let nr = r + dr[d], nc = c + dc[d]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `        if nr < 0 || nr >= 9 || nc < 0 || nc >= 13 { continue }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `        let next = nr * 13 + nc` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `        if maze[nr][nc] != "#" && parent[next] < 0 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `            parent[next] = cell` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `            queue.append(next)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L34: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L35: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L36: `var steps = 0, cell = goal` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `while cell != start {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `    if cell != goal { maze[cell / 13][cell % 13] = "*" }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `    steps += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `    cell = parent[cell]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L42: `print("steps: \(steps)")` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L43: `for row in maze { print(String(row)) }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **544 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 398 tokens. The contiguous original span L13–L43 costs 544 tokens; the complete original source costs 698 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L13: 532 tokens; removes `for r in 0..<9 {` from the dependency chain described above.
- Without L14: 530 tokens; removes `for c in 0..<13 {` from the dependency chain described above.
- Without L15: 507 tokens; removes `if maze[r][c] == "S" { start = r * 13 + c }` from the dependency chain described above.
- Without L16: 507 tokens; removes `if maze[r][c] == "G" { goal = r * 13 + c }` from the dependency chain described above.
- Without L17: 541 tokens; removes `}` from the dependency chain described above.
- Without L18: 542 tokens; removes `}` from the dependency chain described above.
- Without L19: 503 tokens; removes `var parent = [Int](repeating: -1, count: 117), queue = [start], head = 0` from the dependency chain described above.
- Without L20: 535 tokens; removes `parent[start] = start` from the dependency chain described above.
- Without L21: 505 tokens; removes `let dr = [-1, 1, 0, 0], dc = [0, 0, -1, 1]` from the dependency chain described above.
- Without L22: 532 tokens; removes `while head < queue.count {` from the dependency chain described above.
- Without L23: 508 tokens; removes `let cell = queue[head], r = cell / 13, c = cell % 13` from the dependency chain described above.
- Without L24: 537 tokens; removes `head += 1` from the dependency chain described above.
- Without L25: 529 tokens; removes `if cell == goal { break }` from the dependency chain described above.
- Without L26: 531 tokens; removes `for d in 0..<4 {` from the dependency chain described above.
- Without L27: 513 tokens; removes `let nr = r + dr[d], nc = c + dc[d]` from the dependency chain described above.
- Without L28: 503 tokens; removes `if nr < 0 || nr >= 9 || nc < 0 || nc >= 13 { continue }` from the dependency chain described above.
- Without L29: 525 tokens; removes `let next = nr * 13 + nc` from the dependency chain described above.
- Without L30: 513 tokens; removes `if maze[nr][nc] != "#" && parent[next] < 0 {` from the dependency chain described above.
- Without L31: 532 tokens; removes `parent[next] = cell` from the dependency chain described above.
- Without L32: 534 tokens; removes `queue.append(next)` from the dependency chain described above.
- Without L33: 540 tokens; removes `}` from the dependency chain described above.
- Without L34: 541 tokens; removes `}` from the dependency chain described above.
- Without L35: 542 tokens; removes `}` from the dependency chain described above.
- Without L36: 529 tokens; removes `var steps = 0, cell = goal` from the dependency chain described above.
- Without L37: 534 tokens; removes `while cell != start {` from the dependency chain described above.
- Without L38: 507 tokens; removes `if cell != goal { maze[cell / 13][cell % 13] = "*" }` from the dependency chain described above.
- Without L39: 537 tokens; removes `steps += 1` from the dependency chain described above.
- Without L40: 534 tokens; removes `cell = parent[cell]` from the dependency chain described above.
- Without L41: 542 tokens; removes `}` from the dependency chain described above.
- Without L42: 531 tokens; removes `print("steps: \(steps)")` from the dependency chain described above.
- Without L43: 524 tokens; removes `for row in maze { print(String(row)) }` from the dependency chain described above.
