# Task B selection: 88_maze_shortest_path / Java

## Common answer requirements

Connect goal discovery and one-time parent assignment to reconstruction and marked-maze output; establish exactly route cells, moves=route cells minus one, and preservation of S/G.

## Answer and source dependencies

On first discovery of an unvisited nonwall neighbor, the search records its current predecessor and queues the neighbor. That includes the goal. Some implementations stop when the goal is dequeued, some stop after discovering it, and others finish the BFS; the recorded parent route is retained. Starting at goal and repeatedly replacing the current cell by its parent follows the discovery tree backward until start. Exactly one link is followed per move, so a route containing k cells has k-1 moves. The loop excludes start; a dot-only replacement or explicit goal exclusion also preserves G. Only intermediate passage cells are changed to asterisks, or marked in a separate path array and substituted at rendering. The final row printer consumes the changed cells/path overlay.



## Scope and dependency evidence checked after independent review

Bind S/G locations before seeding the search, and establish FIFO queue removal/head advancement. Neighbor coordinates are current coordinates plus one of the four unit directions, so assigning parent[neighbor]=current records the previous adjacent cell only on first discovery; parent/seen marking precedes enqueue and cannot be overwritten by a later visit. Search-loop boundaries precede backtracking; backtracking ends before row output. Distance-based variants initialize start distance0. Each goal-to-start parent transition counts one move: a route with k+1 cells has k edges and k-1 intermediate stars. The start is excluded by the termination test; the goal survives through a dot-only marking guard or explicit goal exclusion. Width bindings and the Zig standard writer association establish how the modified rows are rendered. Exact maze literals are unnecessary for this structural relationship.

Source: `Main.java`. Selected original locations: L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41,L42,L43,L44,L45,L46,L47,L48,L49,L50,L51,L52,L53,L54,L55,L56,L57,L58,L59,L60,L61.

- L19: `        for (int r = 0; r < 9; r++) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `            for (int c = 0; c < 13; c++) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `                if (maze[r][c] == 'S') {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `                    start = r * 13 + c;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `                }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L24: `                if (maze[r][c] == 'G') {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `                    goal = r * 13 + c;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `                }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L27: `            }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L28: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L30: `        Arrays.fill(parent, -1);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `        parent[start] = start;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `        Deque<Integer> queue = new ArrayDeque<>();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `        queue.add(start);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `        int[] dr = {-1, 1, 0, 0}, dc = {0, 0, -1, 1};` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `        while (!queue.isEmpty()) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `            int cell = queue.remove(), r = cell / 13, c = cell % 13;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `            if (cell == goal) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `                break;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `            }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L40: `            for (int d = 0; d < 4; d++) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `                int nr = r + dr[d], nc = c + dc[d];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `                if (nr < 0 || nr >= 9 || nc < 0 || nc >= 13) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L43: `                    continue;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `                }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L45: `                int next = nr * 13 + nc;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `                if (maze[nr][nc] != '#' && parent[next] < 0) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L47: `                    parent[next] = cell;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `                    queue.add(next);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `                }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L50: `            }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L51: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L52: `        int steps = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L53: `        for (int cell = goal; cell != start; cell = parent[cell]) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L54: `            if (cell != goal) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L55: `                maze[cell / 13][cell % 13] = '*';` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L56: `            }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L57: `            steps++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L58: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L59: `        System.out.println("steps: " + steps);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L60: `        for (char[] row : maze) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L61: `            System.out.println(new String(row));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **726 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 438 tokens. The contiguous original span L19–L61 costs 745 tokens; the complete original source costs 1003 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L19: 699 tokens; removes `for (int r = 0; r < 9; r++) {` from the dependency chain described above.
- Without L20: 697 tokens; removes `for (int c = 0; c < 13; c++) {` from the dependency chain described above.
- Without L21: 702 tokens; removes `if (maze[r][c] == 'S') {` from the dependency chain described above.
- Without L22: 705 tokens; removes `start = r * 13 + c;` from the dependency chain described above.
- Without L23: 720 tokens; removes `}` from the dependency chain described above.
- Without L24: 702 tokens; removes `if (maze[r][c] == 'G') {` from the dependency chain described above.
- Without L25: 705 tokens; removes `goal = r * 13 + c;` from the dependency chain described above.
- Without L26: 720 tokens; removes `}` from the dependency chain described above.
- Without L27: 721 tokens; removes `}` from the dependency chain described above.
- Without L28: 722 tokens; removes `}` from the dependency chain described above.
- Without L30: 712 tokens; removes `Arrays.fill(parent, -1);` from the dependency chain described above.
- Without L31: 714 tokens; removes `parent[start] = start;` from the dependency chain described above.
- Without L32: 705 tokens; removes `Deque<Integer> queue = new ArrayDeque<>();` from the dependency chain described above.
- Without L33: 716 tokens; removes `queue.add(start);` from the dependency chain described above.
- Without L34: 683 tokens; removes `int[] dr = {-1, 1, 0, 0}, dc = {0, 0, -1, 1};` from the dependency chain described above.
- Without L35: 710 tokens; removes `while (!queue.isEmpty()) {` from the dependency chain described above.
- Without L36: 686 tokens; removes `int cell = queue.remove(), r = cell / 13, c = cell % 13;` from the dependency chain described above.
- Without L37: 711 tokens; removes `if (cell == goal) {` from the dependency chain described above.
- Without L38: 719 tokens; removes `break;` from the dependency chain described above.
- Without L39: 721 tokens; removes `}` from the dependency chain described above.
- Without L40: 698 tokens; removes `for (int d = 0; d < 4; d++) {` from the dependency chain described above.
- Without L41: 692 tokens; removes `int nr = r + dr[d], nc = c + dc[d];` from the dependency chain described above.
- Without L42: 685 tokens; removes `if (nr < 0 || nr >= 9 || nc < 0 || nc >= 13) {` from the dependency chain described above.
- Without L43: 718 tokens; removes `continue;` from the dependency chain described above.
- Without L44: 720 tokens; removes `}` from the dependency chain described above.
- Without L45: 704 tokens; removes `int next = nr * 13 + nc;` from the dependency chain described above.
- Without L46: 691 tokens; removes `if (maze[nr][nc] != '#' && parent[next] < 0) {` from the dependency chain described above.
- Without L47: 711 tokens; removes `parent[next] = cell;` from the dependency chain described above.
- Without L48: 713 tokens; removes `queue.add(next);` from the dependency chain described above.
- Without L49: 720 tokens; removes `}` from the dependency chain described above.
- Without L50: 721 tokens; removes `}` from the dependency chain described above.
- Without L51: 722 tokens; removes `}` from the dependency chain described above.
- Without L52: 715 tokens; removes `int steps = 0;` from the dependency chain described above.
- Without L53: 693 tokens; removes `for (int cell = goal; cell != start; cell = parent[cell]) {` from the dependency chain described above.
- Without L54: 711 tokens; removes `if (cell != goal) {` from the dependency chain described above.
- Without L55: 697 tokens; removes `maze[cell / 13][cell % 13] = '*';` from the dependency chain described above.
- Without L56: 721 tokens; removes `}` from the dependency chain described above.
- Without L57: 719 tokens; removes `steps++;` from the dependency chain described above.
- Without L58: 722 tokens; removes `}` from the dependency chain described above.
- Without L59: 706 tokens; removes `System.out.println("steps: " + steps);` from the dependency chain described above.
- Without L60: 709 tokens; removes `for (char[] row : maze) {` from the dependency chain described above.
- Without L61: 708 tokens; removes `System.out.println(new String(row));` from the dependency chain described above.
