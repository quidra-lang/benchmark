# Task B selection: 88_maze_shortest_path / C++

## Common answer requirements

Connect goal discovery and one-time parent assignment to reconstruction and marked-maze output; establish exactly route cells, moves=route cells minus one, and preservation of S/G.

## Answer and source dependencies

On first discovery of an unvisited nonwall neighbor, the search records its current predecessor and queues the neighbor. That includes the goal. Some implementations stop when the goal is dequeued, some stop after discovering it, and others finish the BFS; the recorded parent route is retained. Starting at goal and repeatedly replacing the current cell by its parent follows the discovery tree backward until start. Exactly one link is followed per move, so a route containing k cells has k-1 moves. The loop excludes start; a dot-only replacement or explicit goal exclusion also preserves G. Only intermediate passage cells are changed to asterisks, or marked in a separate path array and substituted at rendering. The final row printer consumes the changed cells/path overlay.



## Scope and dependency evidence checked after independent review

Bind S/G locations before seeding the search, and establish FIFO queue removal/head advancement. Neighbor coordinates are current coordinates plus one of the four unit directions, so assigning parent[neighbor]=current records the previous adjacent cell only on first discovery; parent/seen marking precedes enqueue and cannot be overwritten by a later visit. Search-loop boundaries precede backtracking; backtracking ends before row output. Distance-based variants initialize start distance0. Each goal-to-start parent transition counts one move: a route with k+1 cells has k edges and k-1 intermediate stars. The start is excluded by the termination test; the goal survives through a dot-only marking guard or explicit goal exclusion. Width bindings and the Zig standard writer association establish how the modified rows are rendered. Exact maze literals are unnecessary for this structural relationship.

Source: `main.cpp`. Selected original locations: L9,L10,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40.

- L9: `    std::array<int, 117> parent, distance{};` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    parent.fill(-1);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    for (int i = 0; i < 117; i++) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `        if (maze[i / 13][i % 13] == 'S')` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `            start = i;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `        if (maze[i / 13][i % 13] == 'G')` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `            goal = i;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L18: `    std::vector<int> queue = {start};` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `    parent[start] = start;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `    int dr[] = {-1, 1, 0, 0}, dc[] = {0, 0, -1, 1};` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `    for (std::size_t head = 0; head < queue.size(); head++) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `        int v = queue[head], r = v / 13, c = v % 13;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `        for (int d = 0; d < 4; d++) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `            int rr = r + dr[d], cc = c + dc[d];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `            if (rr < 0 || rr >= 9 || cc < 0 || cc >= 13 || maze[rr][cc] == '#')` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `                continue;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `            int w = rr * 13 + cc;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `            if (parent[w] < 0) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `                parent[w] = v;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `                distance[w] = distance[v] + 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `                queue.push_back(w);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `            }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L33: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L34: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L35: `    for (int v = goal; v != start; v = parent[v])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `        if (maze[v / 13][v % 13] == '.')` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `            maze[v / 13][v % 13] = '*';` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `    std::cout << "steps: " << distance[goal] << '\n';` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `    for (const std::string &row : maze)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `        std::cout << row << '\n';` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **658 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 491 tokens. The contiguous original span L9–L40 costs 677 tokens; the complete original source costs 836 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L9: 637 tokens; removes `std::array<int, 117> parent, distance{};` from the dependency chain described above.
- Without L10: 648 tokens; removes `parent.fill(-1);` from the dependency chain described above.
- Without L12: 630 tokens; removes `for (int i = 0; i < 117; i++) {` from the dependency chain described above.
- Without L13: 628 tokens; removes `if (maze[i / 13][i % 13] == 'S')` from the dependency chain described above.
- Without L14: 648 tokens; removes `start = i;` from the dependency chain described above.
- Without L15: 628 tokens; removes `if (maze[i / 13][i % 13] == 'G')` from the dependency chain described above.
- Without L16: 648 tokens; removes `goal = i;` from the dependency chain described above.
- Without L17: 655 tokens; removes `}` from the dependency chain described above.
- Without L18: 641 tokens; removes `std::vector<int> queue = {start};` from the dependency chain described above.
- Without L19: 647 tokens; removes `parent[start] = start;` from the dependency chain described above.
- Without L20: 615 tokens; removes `int dr[] = {-1, 1, 0, 0}, dc[] = {0, 0, -1, 1};` from the dependency chain described above.
- Without L21: 624 tokens; removes `for (std::size_t head = 0; head < queue.size(); head++) {` from the dependency chain described above.
- Without L22: 620 tokens; removes `int v = queue[head], r = v / 13, c = v % 13;` from the dependency chain described above.
- Without L23: 631 tokens; removes `for (int d = 0; d < 4; d++) {` from the dependency chain described above.
- Without L24: 625 tokens; removes `int rr = r + dr[d], cc = c + dc[d];` from the dependency chain described above.
- Without L25: 604 tokens; removes `if (rr < 0 || rr >= 9 || cc < 0 || cc >= 13 || maze[rr][cc] == '#')` from the dependency chain described above.
- Without L26: 651 tokens; removes `continue;` from the dependency chain described above.
- Without L27: 637 tokens; removes `int w = rr * 13 + cc;` from the dependency chain described above.
- Without L28: 640 tokens; removes `if (parent[w] < 0) {` from the dependency chain described above.
- Without L29: 644 tokens; removes `parent[w] = v;` from the dependency chain described above.
- Without L30: 637 tokens; removes `distance[w] = distance[v] + 1;` from the dependency chain described above.
- Without L31: 644 tokens; removes `queue.push_back(w);` from the dependency chain described above.
- Without L32: 653 tokens; removes `}` from the dependency chain described above.
- Without L33: 654 tokens; removes `}` from the dependency chain described above.
- Without L34: 655 tokens; removes `}` from the dependency chain described above.
- Without L35: 628 tokens; removes `for (int v = goal; v != start; v = parent[v])` from the dependency chain described above.
- Without L36: 628 tokens; removes `if (maze[v / 13][v % 13] == '.')` from the dependency chain described above.
- Without L37: 630 tokens; removes `maze[v / 13][v % 13] = '*';` from the dependency chain described above.
- Without L38: 630 tokens; removes `std::cout << "steps: " << distance[goal] << '\n';` from the dependency chain described above.
- Without L39: 640 tokens; removes `for (const std::string &row : maze)` from the dependency chain described above.
- Without L40: 640 tokens; removes `std::cout << row << '\n';` from the dependency chain described above.
