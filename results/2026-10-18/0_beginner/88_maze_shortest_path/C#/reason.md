# Task B selection: 88_maze_shortest_path / C#

## Common answer requirements

Connect goal discovery and one-time parent assignment to reconstruction and marked-maze output; establish exactly route cells, moves=route cells minus one, and preservation of S/G.

## Answer and source dependencies

On first discovery of an unvisited nonwall neighbor, the search records its current predecessor and queues the neighbor. That includes the goal. Some implementations stop when the goal is dequeued, some stop after discovering it, and others finish the BFS; the recorded parent route is retained. Starting at goal and repeatedly replacing the current cell by its parent follows the discovery tree backward until start. Exactly one link is followed per move, so a route containing k cells has k-1 moves. The loop excludes start; a dot-only replacement or explicit goal exclusion also preserves G. Only intermediate passage cells are changed to asterisks, or marked in a separate path array and substituted at rendering. The final row printer consumes the changed cells/path overlay.



## Scope and dependency evidence checked after independent review

Bind S/G locations before seeding the search, and establish FIFO queue removal/head advancement. Neighbor coordinates are current coordinates plus one of the four unit directions, so assigning parent[neighbor]=current records the previous adjacent cell only on first discovery; parent/seen marking precedes enqueue and cannot be overwritten by a later visit. Search-loop boundaries precede backtracking; backtracking ends before row output. Distance-based variants initialize start distance0. Each goal-to-start parent transition counts one move: a route with k+1 cells has k edges and k-1 intermediate stars. The start is excluded by the termination test; the goal survives through a dot-only marking guard or explicit goal exclusion. Width bindings and the Zig standard writer association establish how the modified rows are rendered. Exact maze literals are unnecessary for this structural relationship.

Source: `Program.cs`. Selected original locations: L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41,L42,L43,L44,L45,L46,L47,L48,L49,L50,L51,L52,L53,L54,L55,L56,L57,L58.

- L22: `for (int r = 0; r < 9; r++)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `{` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L24: `    for (int c = 0; c < 13; c++)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `    {` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L26: `        if (maze[r][c] == 'S') start = r * 13 + c;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `        if (maze[r][c] == 'G') goal = r * 13 + c;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L29: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L30: `int[] parent = Enumerable.Repeat(-1, 117).ToArray();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `parent[start] = start;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `var queue = new Queue<int>();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `queue.Enqueue(start);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `int[] dr = { -1, 1, 0, 0 }, dc = { 0, 0, -1, 1 };` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `while (queue.Count > 0)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `{` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L37: `    int cell = queue.Dequeue(), r = cell / 13, c = cell % 13;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `    if (cell == goal) break;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `    for (int d = 0; d < 4; d++)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `    {` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L41: `        int nr = r + dr[d], nc = c + dc[d];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `        if (nr < 0 || nr >= 9 || nc < 0 || nc >= 13) continue;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L43: `        int next = nr * 13 + nc;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `        if (maze[nr][nc] != '#' && parent[next] < 0)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `        {` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L46: `            parent[next] = cell;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L47: `            queue.Enqueue(next);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L49: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L50: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L51: `int steps = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L52: `for (int cell = goal; cell != start; cell = parent[cell])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L53: `{` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L54: `    if (cell != goal) maze[cell / 13][cell % 13] = '*';` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L55: `    steps++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L56: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L57: `Console.WriteLine($"steps: {steps}");` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L58: `foreach (char[] row in maze) Console.WriteLine(new string(row));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **615 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 360 tokens. The contiguous original span L22–L58 costs 615 tokens; the complete original source costs 829 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L22: 592 tokens; removes `for (int r = 0; r < 9; r++)` from the dependency chain described above.
- Without L23: 613 tokens; removes `{` from the dependency chain described above.
- Without L24: 590 tokens; removes `for (int c = 0; c < 13; c++)` from the dependency chain described above.
- Without L25: 612 tokens; removes `{` from the dependency chain described above.
- Without L26: 579 tokens; removes `if (maze[r][c] == 'S') start = r * 13 + c;` from the dependency chain described above.
- Without L27: 579 tokens; removes `if (maze[r][c] == 'G') goal = r * 13 + c;` from the dependency chain described above.
- Without L28: 612 tokens; removes `}` from the dependency chain described above.
- Without L29: 613 tokens; removes `}` from the dependency chain described above.
- Without L30: 589 tokens; removes `int[] parent = Enumerable.Repeat(-1, 117).ToArray();` from the dependency chain described above.
- Without L31: 605 tokens; removes `parent[start] = start;` from the dependency chain described above.
- Without L32: 599 tokens; removes `var queue = new Queue<int>();` from the dependency chain described above.
- Without L33: 607 tokens; removes `queue.Enqueue(start);` from the dependency chain described above.
- Without L34: 570 tokens; removes `int[] dr = { -1, 1, 0, 0 }, dc = { 0, 0, -1, 1 };` from the dependency chain described above.
- Without L35: 603 tokens; removes `while (queue.Count > 0)` from the dependency chain described above.
- Without L36: 613 tokens; removes `{` from the dependency chain described above.
- Without L37: 577 tokens; removes `int cell = queue.Dequeue(), r = cell / 13, c = cell % 13;` from the dependency chain described above.
- Without L38: 601 tokens; removes `if (cell == goal) break;` from the dependency chain described above.
- Without L39: 591 tokens; removes `for (int d = 0; d < 4; d++)` from the dependency chain described above.
- Without L40: 612 tokens; removes `{` from the dependency chain described above.
- Without L41: 583 tokens; removes `int nr = r + dr[d], nc = c + dc[d];` from the dependency chain described above.
- Without L42: 575 tokens; removes `if (nr < 0 || nr >= 9 || nc < 0 || nc >= 13) continue;` from the dependency chain described above.
- Without L43: 595 tokens; removes `int next = nr * 13 + nc;` from the dependency chain described above.
- Without L44: 584 tokens; removes `if (maze[nr][nc] != '#' && parent[next] < 0)` from the dependency chain described above.
- Without L45: 611 tokens; removes `{` from the dependency chain described above.
- Without L46: 602 tokens; removes `parent[next] = cell;` from the dependency chain described above.
- Without L47: 604 tokens; removes `queue.Enqueue(next);` from the dependency chain described above.
- Without L48: 611 tokens; removes `}` from the dependency chain described above.
- Without L49: 612 tokens; removes `}` from the dependency chain described above.
- Without L50: 613 tokens; removes `}` from the dependency chain described above.
- Without L51: 606 tokens; removes `int steps = 0;` from the dependency chain described above.
- Without L52: 586 tokens; removes `for (int cell = goal; cell != start; cell = parent[cell])` from the dependency chain described above.
- Without L53: 613 tokens; removes `{` from the dependency chain described above.
- Without L54: 579 tokens; removes `if (cell != goal) maze[cell / 13][cell % 13] = '*';` from the dependency chain described above.
- Without L55: 610 tokens; removes `steps++;` from the dependency chain described above.
- Without L56: 613 tokens; removes `}` from the dependency chain described above.
- Without L57: 598 tokens; removes `Console.WriteLine($"steps: {steps}");` from the dependency chain described above.
- Without L58: 588 tokens; removes `foreach (char[] row in maze) Console.WriteLine(new string(row));` from the dependency chain described above.
