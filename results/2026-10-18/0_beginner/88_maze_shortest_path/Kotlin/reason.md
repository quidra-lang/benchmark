# Task B selection: 88_maze_shortest_path / Kotlin

## Common answer requirements

Connect goal discovery and one-time parent assignment to reconstruction and marked-maze output; establish exactly route cells, moves=route cells minus one, and preservation of S/G.

## Answer and source dependencies

On first discovery of an unvisited nonwall neighbor, the search records its current predecessor and queues the neighbor. That includes the goal. Some implementations stop when the goal is dequeued, some stop after discovering it, and others finish the BFS; the recorded parent route is retained. Starting at goal and repeatedly replacing the current cell by its parent follows the discovery tree backward until start. Exactly one link is followed per move, so a route containing k cells has k-1 moves. The loop excludes start; a dot-only replacement or explicit goal exclusion also preserves G. Only intermediate passage cells are changed to asterisks, or marked in a separate path array and substituted at rendering. The final row printer consumes the changed cells/path overlay.



## Scope and dependency evidence checked after independent review

Bind S/G locations before seeding the search, and establish FIFO queue removal/head advancement. Neighbor coordinates are current coordinates plus one of the four unit directions, so assigning parent[neighbor]=current records the previous adjacent cell only on first discovery; parent/seen marking precedes enqueue and cannot be overwritten by a later visit. Search-loop boundaries precede backtracking; backtracking ends before row output. Distance-based variants initialize start distance0. Each goal-to-start parent transition counts one move: a route with k+1 cells has k edges and k-1 intermediate stars. The start is excluded by the termination test; the goal survives through a dot-only marking guard or explicit goal exclusion. Width bindings and the Zig standard writer association establish how the modified rows are rendered. Exact maze literals are unnecessary for this structural relationship.

Source: `main.kt`. Selected original locations: L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41,L42,L43,L44,L45,L46,L47,L48,L49,L50,L51,L52.

- L16: `    for (r in 0 until 9) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `        for (c in 0 until 13) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `            if (maze[r][c] == 'S') start = r * 13 + c` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `            if (maze[r][c] == 'G') goal = r * 13 + c` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L21: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L22: `    val parent = IntArray(117) { -1 }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `    parent[start] = start` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `    val queue = ArrayDeque<Int>()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `    queue.addLast(start)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `    val dr = intArrayOf(-1, 1, 0, 0)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `    val dc = intArrayOf(0, 0, -1, 1)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `    while (queue.isNotEmpty()) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `        val cell = queue.removeFirst()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `        val r = cell / 13` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `        val c = cell % 13` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `        if (cell == goal) break` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `        for (d in 0 until 4) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `            val nr = r + dr[d]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `            val nc = c + dc[d]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `            if (nr !in 0 until 9 || nc !in 0 until 13) continue` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `            val next = nr * 13 + nc` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `            if (maze[nr][nc] != '#' && parent[next] < 0) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `                parent[next] = cell` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `                queue.addLast(next)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `            }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L42: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L43: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L44: `    var steps = 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `    var cell = goal` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `    while (cell != start) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L47: `        if (cell != goal) maze[cell / 13][cell % 13] = '*'` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `        steps++` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `        cell = parent[cell]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L50: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L51: `    println("steps: $steps")` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L52: `    for (row in maze) println(row.concatToString())` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **592 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 348 tokens. The contiguous original span L16–L52 costs 592 tokens; the complete original source costs 776 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L16: 575 tokens; removes `for (r in 0 until 9) {` from the dependency chain described above.
- Without L17: 573 tokens; removes `for (c in 0 until 13) {` from the dependency chain described above.
- Without L18: 556 tokens; removes `if (maze[r][c] == 'S') start = r * 13 + c` from the dependency chain described above.
- Without L19: 556 tokens; removes `if (maze[r][c] == 'G') goal = r * 13 + c` from the dependency chain described above.
- Without L20: 588 tokens; removes `}` from the dependency chain described above.
- Without L21: 589 tokens; removes `}` from the dependency chain described above.
- Without L22: 570 tokens; removes `val parent = IntArray(117) { -1 }` from the dependency chain described above.
- Without L23: 582 tokens; removes `parent[start] = start` from the dependency chain described above.
- Without L24: 577 tokens; removes `val queue = ArrayDeque<Int>()` from the dependency chain described above.
- Without L25: 583 tokens; removes `queue.addLast(start)` from the dependency chain described above.
- Without L26: 568 tokens; removes `val dr = intArrayOf(-1, 1, 0, 0)` from the dependency chain described above.
- Without L27: 568 tokens; removes `val dc = intArrayOf(0, 0, -1, 1)` from the dependency chain described above.
- Without L28: 577 tokens; removes `while (queue.isNotEmpty()) {` from the dependency chain described above.
- Without L29: 577 tokens; removes `val cell = queue.removeFirst()` from the dependency chain described above.
- Without L30: 577 tokens; removes `val r = cell / 13` from the dependency chain described above.
- Without L31: 577 tokens; removes `val c = cell % 13` from the dependency chain described above.
- Without L32: 578 tokens; removes `if (cell == goal) break` from the dependency chain described above.
- Without L33: 574 tokens; removes `for (d in 0 until 4) {` from the dependency chain described above.
- Without L34: 574 tokens; removes `val nr = r + dr[d]` from the dependency chain described above.
- Without L35: 574 tokens; removes `val nc = c + dc[d]` from the dependency chain described above.
- Without L36: 558 tokens; removes `if (nr !in 0 until 9 || nc !in 0 until 13) continue` from the dependency chain described above.
- Without L37: 572 tokens; removes `val next = nr * 13 + nc` from the dependency chain described above.
- Without L38: 558 tokens; removes `if (maze[nr][nc] != '#' && parent[next] < 0) {` from the dependency chain described above.
- Without L39: 579 tokens; removes `parent[next] = cell` from the dependency chain described above.
- Without L40: 580 tokens; removes `queue.addLast(next)` from the dependency chain described above.
- Without L41: 587 tokens; removes `}` from the dependency chain described above.
- Without L42: 588 tokens; removes `}` from the dependency chain described above.
- Without L43: 589 tokens; removes `}` from the dependency chain described above.
- Without L44: 583 tokens; removes `var steps = 0` from the dependency chain described above.
- Without L45: 583 tokens; removes `var cell = goal` from the dependency chain described above.
- Without L46: 579 tokens; removes `while (cell != start) {` from the dependency chain described above.
- Without L47: 556 tokens; removes `if (cell != goal) maze[cell / 13][cell % 13] = '*'` from the dependency chain described above.
- Without L48: 587 tokens; removes `steps++` from the dependency chain described above.
- Without L49: 581 tokens; removes `cell = parent[cell]` from the dependency chain described above.
- Without L50: 589 tokens; removes `}` from the dependency chain described above.
- Without L51: 580 tokens; removes `println("steps: $steps")` from the dependency chain described above.
- Without L52: 570 tokens; removes `for (row in maze) println(row.concatToString())` from the dependency chain described above.
