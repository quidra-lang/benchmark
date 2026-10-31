# Task B selection: 88_maze_shortest_path / Dart

## Common answer requirements

Connect goal discovery and one-time parent assignment to reconstruction and marked-maze output; establish exactly route cells, moves=route cells minus one, and preservation of S/G.

## Answer and source dependencies

On first discovery of an unvisited nonwall neighbor, the search records its current predecessor and queues the neighbor. That includes the goal. Some implementations stop when the goal is dequeued, some stop after discovering it, and others finish the BFS; the recorded parent route is retained. Starting at goal and repeatedly replacing the current cell by its parent follows the discovery tree backward until start. Exactly one link is followed per move, so a route containing k cells has k-1 moves. The loop excludes start; a dot-only replacement or explicit goal exclusion also preserves G. Only intermediate passage cells are changed to asterisks, or marked in a separate path array and substituted at rendering. The final row printer consumes the changed cells/path overlay.



## Scope and dependency evidence checked after independent review

Bind S/G locations before seeding the search, and establish FIFO queue removal/head advancement. Neighbor coordinates are current coordinates plus one of the four unit directions, so assigning parent[neighbor]=current records the previous adjacent cell only on first discovery; parent/seen marking precedes enqueue and cannot be overwritten by a later visit. Search-loop boundaries precede backtracking; backtracking ends before row output. Distance-based variants initialize start distance0. Each goal-to-start parent transition counts one move: a route with k+1 cells has k edges and k-1 intermediate stars. The start is excluded by the termination test; the goal survives through a dot-only marking guard or explicit goal exclusion. Width bindings and the Zig standard writer association establish how the modified rows are rendered. Exact maze literals are unnecessary for this structural relationship.

Source: `main.dart`. Selected original locations: L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41.

- L14: `  final start = maze.indexOf('S');` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `  final goal = maze.indexOf('G');` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `  final parent = List.filled(117, -1);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `  parent[start] = start;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `  final queue = [start];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `  const directions = [(-1, 0), (1, 0), (0, -1), (0, 1)];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `  for (var head = 0; head < queue.length; head++) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `    final v = queue[head];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `    if (v == goal) break;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `    for (final d in directions) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `      final r = v ~/ 13 + d.$1, c = v % 13 + d.$2;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `      if (r < 0 || r >= 9 || c < 0 || c >= 13) continue;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `      final u = r * 13 + c;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `      if (maze[u] != '#' && parent[u] == -1) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `        parent[u] = v;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `        queue.add(u);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `      }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L31: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L32: `  }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L33: `  var current = goal, steps = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `  while (current != start) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `    if (current != goal) maze[current] = '*';` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `    current = parent[current];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `    steps++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `  }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L39: `  print('steps: $steps');` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `  for (var r = 0; r < 9; r++) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `    print(maze.sublist(r * 13, r * 13 + 13).join());` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **501 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 330 tokens. The contiguous original span L14–L41 costs 501 tokens; the complete original source costs 655 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L14: 483 tokens; removes `final start = maze.indexOf('S');` from the dependency chain described above.
- Without L15: 483 tokens; removes `final goal = maze.indexOf('G');` from the dependency chain described above.
- Without L16: 480 tokens; removes `final parent = List.filled(117, -1);` from the dependency chain described above.
- Without L17: 490 tokens; removes `parent[start] = start;` from the dependency chain described above.
- Without L18: 489 tokens; removes `final queue = [start];` from the dependency chain described above.
- Without L19: 458 tokens; removes `const directions = [(-1, 0), (1, 0), (0, -1), (0, 1)];` from the dependency chain described above.
- Without L20: 473 tokens; removes `for (var head = 0; head < queue.length; head++) {` from the dependency chain described above.
- Without L21: 488 tokens; removes `final v = queue[head];` from the dependency chain described above.
- Without L22: 487 tokens; removes `if (v == goal) break;` from the dependency chain described above.
- Without L23: 486 tokens; removes `for (final d in directions) {` from the dependency chain described above.
- Without L24: 461 tokens; removes `final r = v ~/ 13 + d.$1, c = v % 13 + d.$2;` from the dependency chain described above.
- Without L25: 461 tokens; removes `if (r < 0 || r >= 9 || c < 0 || c >= 13) continue;` from the dependency chain described above.
- Without L26: 481 tokens; removes `final u = r * 13 + c;` from the dependency chain described above.
- Without L27: 470 tokens; removes `if (maze[u] != '#' && parent[u] == -1) {` from the dependency chain described above.
- Without L28: 489 tokens; removes `parent[u] = v;` from the dependency chain described above.
- Without L29: 491 tokens; removes `queue.add(u);` from the dependency chain described above.
- Without L30: 497 tokens; removes `}` from the dependency chain described above.
- Without L31: 498 tokens; removes `}` from the dependency chain described above.
- Without L32: 498 tokens; removes `}` from the dependency chain described above.
- Without L33: 484 tokens; removes `var current = goal, steps = 0;` from the dependency chain described above.
- Without L34: 488 tokens; removes `while (current != start) {` from the dependency chain described above.
- Without L35: 478 tokens; removes `if (current != goal) maze[current] = '*';` from the dependency chain described above.
- Without L36: 490 tokens; removes `current = parent[current];` from the dependency chain described above.
- Without L37: 496 tokens; removes `steps++;` from the dependency chain described above.
- Without L38: 498 tokens; removes `}` from the dependency chain described above.
- Without L39: 488 tokens; removes `print('steps: $steps');` from the dependency chain described above.
- Without L40: 475 tokens; removes `for (var r = 0; r < 9; r++) {` from the dependency chain described above.
- Without L41: 467 tokens; removes `print(maze.sublist(r * 13, r * 13 + 13).join());` from the dependency chain described above.
