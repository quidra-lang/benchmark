# Task B selection: 80_graph_traversal / C++

## Common answer requirements

Explain DFS versus FIFO BFS over component 0; trace first reach of vertex 7 and visit-mark timing; explain component coverage for omitted vertices independently of visit order.

## Answer and source dependencies

Ascending neighbors give DFS 0,2,7,5,3,8: recursive DFS marks 7 on entry after edge 2→7, before exploring its neighbors. FIFO BFS gives 0,2,5,7,3,8: processing 0 enqueues 2 and 5; processing 2 first discovers/enqueues 7 and immediately marks it, so the edge from 5 does not enqueue it again. Both visit component {0,2,3,5,7,8}. The component pass uses fresh visited state, scans every vertex 0 through 8, starts a traversal at each unseen vertex and sorts each resulting membership list (or collects newly visited indices). Thus {1,4,6} is still recorded as the second component. Recursion versus queue scheduling changes order without changing reachability.



## Scope and dependency evidence checked after independent review

The DFS helper and graph-building loops must finish before traversal calls. BFS visit-at-enqueue happens within the neighbor guard, and the neighbor/queue loops finish before visited is cleared for the independent component pass. Empty order/component collections establish fresh result accumulation. These boundaries and initial states support DFS0,2,7,5,3,8, BFS0,2,5,7,3,8, first discovery of7 from2, and the separate component{1,4,6}.

Source: `main.cpp`. Selected original locations: L6,L7,L8,L9,L10,L11,L12,L13,L16,L17,L18,L19,L20,L21,L22,L27,L28,L29,L31,L32,L34,L35,L36,L37,L38,L39,L41,L42,L43,L44,L45,L46,L47,L48.

- L6: `void dfs(int v, const std::array<std::array<bool, 9>, 9> &graph, std::array<bool, 9> &seen,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `         std::vector<int> &order) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `    seen[v] = true;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `    order.push_back(v);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    for (int w = 0; w < 9; w++)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `        if (graph[v][w] && !seen[w])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `            dfs(w, graph, seen, order);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L16: `    std::array<std::array<bool, 9>, 9> graph{};` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    int edges[][2] = {{5, 0}, {3, 8}, {7, 2}, {1, 6}, {0, 2}, {5, 3}, {7, 5}, {6, 4}, {8, 7}};` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `    for (const int(&e)[2] : edges)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `        graph[e[0]][e[1]] = graph[e[1]][e[0]] = true;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `    std::array<bool, 9> seen{};` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `    std::vector<int> order;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `    dfs(0, graph, seen, order);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `    seen.fill(false);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `    std::vector<int> queue = {0};` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `    seen[0] = true;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `    for (std::size_t head = 0; head < queue.size(); head++) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `        int v = queue[head];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `        for (int w = 0; w < 9; w++)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `            if (graph[v][w] && !seen[w]) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `                seen[w] = true;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `                queue.push_back(w);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `            }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L39: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L41: `    seen.fill(false);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `    std::vector<std::vector<int>> components;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L43: `    for (int v = 0; v < 9; v++)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `        if (!seen[v]) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `            components.emplace_back();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `            std::vector<int> &component = components.back();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L47: `            dfs(v, graph, seen, component);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `            std::sort(component.begin(), component.end());` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **663 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 653 tokens. The contiguous original span L6–L48 costs 771 tokens; the complete original source costs 949 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L6: 616 tokens; removes `void dfs(int v, const std::array<std::array<bool, 9>, 9> &graph, std::array<bool, 9> &seen,` from the dependency chain described above.
- Without L7: 647 tokens; removes `std::vector<int> &order) {` from the dependency chain described above.
- Without L8: 652 tokens; removes `seen[v] = true;` from the dependency chain described above.
- Without L9: 652 tokens; removes `order.push_back(v);` from the dependency chain described above.
- Without L10: 639 tokens; removes `for (int w = 0; w < 9; w++)` from the dependency chain described above.
- Without L11: 641 tokens; removes `if (graph[v][w] && !seen[w])` from the dependency chain described above.
- Without L12: 645 tokens; removes `dfs(w, graph, seen, order);` from the dependency chain described above.
- Without L13: 661 tokens; removes `}` from the dependency chain described above.
- Without L16: 639 tokens; removes `std::array<std::array<bool, 9>, 9> graph{};` from the dependency chain described above.
- Without L17: 578 tokens; removes `int edges[][2] = {{5, 0}, {3, 8}, {7, 2}, {1, 6}, {0, 2}, {5, 3}, {7, 5}, {6, 4}, {8, 7}};` from the dependency chain described above.
- Without L18: 643 tokens; removes `for (const int(&e)[2] : edges)` from the dependency chain described above.
- Without L19: 630 tokens; removes `graph[e[0]][e[1]] = graph[e[1]][e[0]] = true;` from the dependency chain described above.
- Without L20: 647 tokens; removes `std::array<bool, 9> seen{};` from the dependency chain described above.
- Without L21: 652 tokens; removes `std::vector<int> order;` from the dependency chain described above.
- Without L22: 647 tokens; removes `dfs(0, graph, seen, order);` from the dependency chain described above.
- Without L27: 654 tokens; removes `seen.fill(false);` from the dependency chain described above.
- Without L28: 646 tokens; removes `std::vector<int> queue = {0};` from the dependency chain described above.
- Without L29: 652 tokens; removes `seen[0] = true;` from the dependency chain described above.
- Without L31: 629 tokens; removes `for (std::size_t head = 0; head < queue.size(); head++) {` from the dependency chain described above.
- Without L32: 649 tokens; removes `int v = queue[head];` from the dependency chain described above.
- Without L34: 638 tokens; removes `for (int w = 0; w < 9; w++)` from the dependency chain described above.
- Without L35: 638 tokens; removes `if (graph[v][w] && !seen[w]) {` from the dependency chain described above.
- Without L36: 649 tokens; removes `seen[w] = true;` from the dependency chain described above.
- Without L37: 649 tokens; removes `queue.push_back(w);` from the dependency chain described above.
- Without L38: 658 tokens; removes `}` from the dependency chain described above.
- Without L39: 660 tokens; removes `}` from the dependency chain described above.
- Without L41: 654 tokens; removes `seen.fill(false);` from the dependency chain described above.
- Without L42: 648 tokens; removes `std::vector<std::vector<int>> components;` from the dependency chain described above.
- Without L43: 639 tokens; removes `for (int v = 0; v < 9; v++)` from the dependency chain described above.
- Without L44: 649 tokens; removes `if (!seen[v]) {` from the dependency chain described above.
- Without L45: 651 tokens; removes `components.emplace_back();` from the dependency chain described above.
- Without L46: 641 tokens; removes `std::vector<int> &component = components.back();` from the dependency chain described above.
- Without L47: 645 tokens; removes `dfs(v, graph, seen, component);` from the dependency chain described above.
- Without L48: 641 tokens; removes `std::sort(component.begin(), component.end());` from the dependency chain described above.
