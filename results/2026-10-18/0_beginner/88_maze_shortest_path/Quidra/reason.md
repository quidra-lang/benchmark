# Task B selection: 88_maze_shortest_path / Quidra

## Common answer requirements

Connect goal discovery and one-time parent assignment to reconstruction and marked-maze output; establish exactly route cells, moves=route cells minus one, and preservation of S/G.

## Answer and source dependencies

On first discovery of an unvisited nonwall neighbor, the search records its current predecessor and queues the neighbor. That includes the goal. Some implementations stop when the goal is dequeued, some stop after discovering it, and others finish the BFS; the recorded parent route is retained. Starting at goal and repeatedly replacing the current cell by its parent follows the discovery tree backward until start. Exactly one link is followed per move, so a route containing k cells has k-1 moves. The loop excludes start; a dot-only replacement or explicit goal exclusion also preserves G. Only intermediate passage cells are changed to asterisks, or marked in a separate path array and substituted at rendering. The final row printer consumes the changed cells/path overlay.



## Scope and dependency evidence checked after independent review

Bind S/G locations before seeding the search, and establish FIFO queue removal/head advancement. Neighbor coordinates are current coordinates plus one of the four unit directions, so assigning parent[neighbor]=current records the previous adjacent cell only on first discovery; parent/seen marking precedes enqueue and cannot be overwritten by a later visit. Search-loop boundaries precede backtracking; backtracking ends before row output. Distance-based variants initialize start distance0. Each goal-to-start parent transition counts one move: a route with k+1 cells has k edges and k-1 intermediate stars. The start is excluded by the termination test; the goal survives through a dot-only marking guard or explicit goal exclusion. Width bindings and the Zig standard writer association establish how the modified rows are rendered. Exact maze literals are unnecessary for this structural relationship.

Source: `main.qui`. Selected original locations: L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41,L42,L43,L44,L45,L46,L47,L48,L49,L50,L51,L52,L53,L54.

- L14: `for 0 <= int r < 9` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    for 0 <= int c < 13` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `        if maze[r][c] == "S"` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `            start = r * 13 + c` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `        if maze[r][c] == "G"` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `            goal = r * 13 + c` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `int[] parent = array(117, fill = -1)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `parent[start] = start` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `int[] queue = [start]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `int head = 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `int[] dr = [-1, 1, 0, 0]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `int[] dc = [0, 0, -1, 1]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `while head < int(len(queue)) and parent[goal] == -1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `    int current = queue[head]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `    head += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `    int r = current / 13` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `    int c = current % 13` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `    for 0 <= int direction < 4` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `        int nr = r + dr[direction]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `        int nc = c + dc[direction]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `        if 0 <= nr < 9 and 0 <= nc < 13` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `            int neighbor = nr * 13 + nc` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `            if maze[nr][nc] != "#" and parent[neighbor] == -1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `                parent[neighbor] = current` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `                queue = queue.append(neighbor)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `bool[] path = array(117, fill = false)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `int steps = 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `int current = goal` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `while current != start` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L43: `    path[current] = true` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `    current = parent[current]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `    steps += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `print("steps: {steps}{NL}")` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L47: `for 0 <= int r < 9` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `    string line = ""` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `    for 0 <= int c < 13` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L50: `        string character = maze[r][c]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L51: `        if path[r * 13 + c] and character == "."` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L52: `            character = "*"` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L53: `        line += character` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L54: `    print(line + NL)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **622 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 488 tokens. The contiguous original span L14–L54 costs 622 tokens; the complete original source costs 759 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L14: 608 tokens; removes `for 0 <= int r < 9` from the dependency chain described above.
- Without L15: 606 tokens; removes `for 0 <= int c < 13` from the dependency chain described above.
- Without L16: 604 tokens; removes `if maze[r][c] == "S"` from the dependency chain described above.
- Without L17: 604 tokens; removes `start = r * 13 + c` from the dependency chain described above.
- Without L18: 604 tokens; removes `if maze[r][c] == "G"` from the dependency chain described above.
- Without L19: 604 tokens; removes `goal = r * 13 + c` from the dependency chain described above.
- Without L20: 600 tokens; removes `int[] parent = array(117, fill = -1)` from the dependency chain described above.
- Without L21: 613 tokens; removes `parent[start] = start` from the dependency chain described above.
- Without L22: 611 tokens; removes `int[] queue = [start]` from the dependency chain described above.
- Without L23: 614 tokens; removes `int head = 0` from the dependency chain described above.
- Without L24: 601 tokens; removes `int[] dr = [-1, 1, 0, 0]` from the dependency chain described above.
- Without L25: 601 tokens; removes `int[] dc = [0, 0, -1, 1]` from the dependency chain described above.
- Without L26: 596 tokens; removes `while head < int(len(queue)) and parent[goal] == -1` from the dependency chain described above.
- Without L27: 610 tokens; removes `int current = queue[head]` from the dependency chain described above.
- Without L28: 615 tokens; removes `head += 1` from the dependency chain described above.
- Without L29: 608 tokens; removes `int r = current / 13` from the dependency chain described above.
- Without L30: 608 tokens; removes `int c = current % 13` from the dependency chain described above.
- Without L31: 607 tokens; removes `for 0 <= int direction < 4` from the dependency chain described above.
- Without L32: 605 tokens; removes `int nr = r + dr[direction]` from the dependency chain described above.
- Without L33: 605 tokens; removes `int nc = c + dc[direction]` from the dependency chain described above.
- Without L34: 595 tokens; removes `if 0 <= nr < 9 and 0 <= nc < 13` from the dependency chain described above.
- Without L35: 602 tokens; removes `int neighbor = nr * 13 + nc` from the dependency chain described above.
- Without L36: 591 tokens; removes `if maze[nr][nc] != "#" and parent[neighbor] == -1` from the dependency chain described above.
- Without L37: 609 tokens; removes `parent[neighbor] = current` from the dependency chain described above.
- Without L38: 607 tokens; removes `queue = queue.append(neighbor)` from the dependency chain described above.
- Without L39: 601 tokens; removes `bool[] path = array(117, fill = false)` from the dependency chain described above.
- Without L40: 614 tokens; removes `int steps = 0` from the dependency chain described above.
- Without L41: 614 tokens; removes `int current = goal` from the dependency chain described above.
- Without L42: 614 tokens; removes `while current != start` from the dependency chain described above.
- Without L43: 612 tokens; removes `path[current] = true` from the dependency chain described above.
- Without L44: 612 tokens; removes `current = parent[current]` from the dependency chain described above.
- Without L45: 615 tokens; removes `steps += 1` from the dependency chain described above.
- Without L46: 607 tokens; removes `print("steps: {steps}{NL}")` from the dependency chain described above.
- Without L47: 608 tokens; removes `for 0 <= int r < 9` from the dependency chain described above.
- Without L48: 612 tokens; removes `string line = ""` from the dependency chain described above.
- Without L49: 606 tokens; removes `for 0 <= int c < 13` from the dependency chain described above.
- Without L50: 606 tokens; removes `string character = maze[r][c]` from the dependency chain described above.
- Without L51: 594 tokens; removes `if path[r * 13 + c] and character == "."` from the dependency chain described above.
- Without L52: 611 tokens; removes `character = "*"` from the dependency chain described above.
- Without L53: 614 tokens; removes `line += character` from the dependency chain described above.
- Without L54: 612 tokens; removes `print(line + NL)` from the dependency chain described above.
