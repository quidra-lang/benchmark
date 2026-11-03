# Task B selection: 88_maze_shortest_path / Python

## Common answer requirements

Connect goal discovery and one-time parent assignment to reconstruction and marked-maze output; establish exactly route cells, moves=route cells minus one, and preservation of S/G.

## Answer and source dependencies

On first discovery of an unvisited nonwall neighbor, the search records its current predecessor and queues the neighbor. That includes the goal. Some implementations stop when the goal is dequeued, some stop after discovering it, and others finish the BFS; the recorded parent route is retained. Starting at goal and repeatedly replacing the current cell by its parent follows the discovery tree backward until start. Exactly one link is followed per move, so a route containing k cells has k-1 moves. The loop excludes start; a dot-only replacement or explicit goal exclusion also preserves G. Only intermediate passage cells are changed to asterisks, or marked in a separate path array and substituted at rendering. The final row printer consumes the changed cells/path overlay.



## Scope and dependency evidence checked after independent review

Bind S/G locations before seeding the search, and establish FIFO queue removal/head advancement. Neighbor coordinates are current coordinates plus one of the four unit directions, so assigning parent[neighbor]=current records the previous adjacent cell only on first discovery; parent/seen marking precedes enqueue and cannot be overwritten by a later visit. Search-loop boundaries precede backtracking; backtracking ends before row output. Distance-based variants initialize start distance0. Each goal-to-start parent transition counts one move: a route with k+1 cells has k edges and k-1 intermediate stars. The start is excluded by the termination test; the goal survives through a dot-only marking guard or explicit goal exclusion. Width bindings and the Zig standard writer association establish how the modified rows are rendered. Exact maze literals are unnecessary for this structural relationship.

Source: `main.py`. Selected original locations: L1,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40.

- L1: `from collections import deque` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `height, width = len(rows), len(rows[0])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `maze = list("".join(rows))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `start, goal = maze.index("S"), maze.index("G")` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `parent = {start: start}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `queue = deque([start])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `while queue:` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `    cell = queue.popleft()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `    if cell == goal:` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `        break` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `    row, column = divmod(cell, width)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `    for dr, dc in [(-1, 0), (1, 0), (0, -1), (0, 1)]:` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `        r, c = row + dr, column + dc` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `        if 0 <= r < height and 0 <= c < width:` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `            neighbor = r * width + c` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `            if maze[neighbor] != "#" and neighbor not in parent:` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `                parent[neighbor] = cell` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `                queue.append(neighbor)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `steps = 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `cell = goal` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `while cell != start:` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `    steps += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `    if maze[cell] == ".":` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `        maze[cell] = "*"` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `    cell = parent[cell]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `print(f"steps: {steps}")` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `for offset in range(0, len(maze), width):` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `    print("".join(maze[offset : offset + width]))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **423 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 252 tokens. The contiguous original span L1–L40 costs 540 tokens; the complete original source costs 540 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 415 tokens; removes `from collections import deque` from the dependency chain described above.
- Without L14: 402 tokens; removes `height, width = len(rows), len(rows[0])` from the dependency chain described above.
- Without L15: 408 tokens; removes `maze = list("".join(rows))` from the dependency chain described above.
- Without L16: 397 tokens; removes `start, goal = maze.index("S"), maze.index("G")` from the dependency chain described above.
- Without L17: 412 tokens; removes `parent = {start: start}` from the dependency chain described above.
- Without L18: 412 tokens; removes `queue = deque([start])` from the dependency chain described above.
- Without L19: 418 tokens; removes `while queue:` from the dependency chain described above.
- Without L20: 412 tokens; removes `cell = queue.popleft()` from the dependency chain described above.
- Without L21: 413 tokens; removes `if cell == goal:` from the dependency chain described above.
- Without L22: 419 tokens; removes `break` from the dependency chain described above.
- Without L23: 407 tokens; removes `row, column = divmod(cell, width)` from the dependency chain described above.
- Without L24: 378 tokens; removes `for dr, dc in [(-1, 0), (1, 0), (0, -1), (0, 1)]:` from the dependency chain described above.
- Without L25: 401 tokens; removes `r, c = row + dr, column + dc` from the dependency chain described above.
- Without L26: 396 tokens; removes `if 0 <= r < height and 0 <= c < width:` from the dependency chain described above.
- Without L27: 406 tokens; removes `neighbor = r * width + c` from the dependency chain described above.
- Without L28: 396 tokens; removes `if maze[neighbor] != "#" and neighbor not in parent:` from the dependency chain described above.
- Without L29: 410 tokens; removes `parent[neighbor] = cell` from the dependency chain described above.
- Without L30: 412 tokens; removes `queue.append(neighbor)` from the dependency chain described above.
- Without L31: 417 tokens; removes `steps = 0` from the dependency chain described above.
- Without L32: 417 tokens; removes `cell = goal` from the dependency chain described above.
- Without L33: 414 tokens; removes `while cell != start:` from the dependency chain described above.
- Without L34: 416 tokens; removes `steps += 1` from the dependency chain described above.
- Without L35: 408 tokens; removes `if maze[cell] == ".":` from the dependency chain described above.
- Without L36: 410 tokens; removes `maze[cell] = "*"` from the dependency chain described above.
- Without L37: 413 tokens; removes `cell = parent[cell]` from the dependency chain described above.
- Without L38: 410 tokens; removes `print(f"steps: {steps}")` from the dependency chain described above.
- Without L39: 402 tokens; removes `for offset in range(0, len(maze), width):` from the dependency chain described above.
- Without L40: 400 tokens; removes `print("".join(maze[offset : offset + width]))` from the dependency chain described above.
