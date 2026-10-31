# Task B selection: 80_graph_traversal / C

## Common answer requirements

Explain DFS versus FIFO BFS over component 0; trace first reach of vertex 7 and visit-mark timing; explain component coverage for omitted vertices independently of visit order.

## Answer and source dependencies

Ascending neighbors give DFS 0,2,7,5,3,8: recursive DFS marks 7 on entry after edge 2→7, before exploring its neighbors. FIFO BFS gives 0,2,5,7,3,8: processing 0 enqueues 2 and 5; processing 2 first discovers/enqueues 7 and immediately marks it, so the edge from 5 does not enqueue it again. Both visit component {0,2,3,5,7,8}. The component pass uses fresh visited state, scans every vertex 0 through 8, starts a traversal at each unseen vertex and sorts each resulting membership list (or collects newly visited indices). Thus {1,4,6} is still recorded as the second component. Recursion versus queue scheduling changes order without changing reachability.



## Scope and dependency evidence checked after independent review

The DFS helper and graph-building loops must finish before traversal calls. BFS visit-at-enqueue happens within the neighbor guard, and the neighbor/queue loops finish before visited is cleared for the independent component pass. Empty order/component collections establish fresh result accumulation. These boundaries and initial states support DFS0,2,7,5,3,8, BFS0,2,5,7,3,8, first discovery of7 from2, and the separate component{1,4,6}.

Source: `main.c`. Selected original locations: L5,L6,L7,L8,L9,L10,L11,L13,L14,L15,L18,L19,L20,L21,L22,L23,L28,L29,L30,L31,L33,L34,L35,L36,L37,L38,L39,L40,L41,L43,L44,L45,L46,L47,L48,L49,L50.

- L5: `void dfs(int v, int graph[9][9], int *seen, int *order, int *length) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `    seen[v] = 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `    order[(*length)++] = v;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `    for (int w = 0; w < 9; w++)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `        if (graph[v][w] && !seen[w])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `            dfs(w, graph, seen, order, length);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L13: `int compare(const void *a, const void *b) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    return *(const int *)a - *(const int *)b;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L18: `    int graph[9][9] = {{0}};` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `    int edges[][2] = {{5, 0}, {3, 8}, {7, 2}, {1, 6}, {0, 2}, {5, 3}, {7, 5}, {6, 4}, {8, 7}};` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `    for (int i = 0; i < 9; i++)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `        graph[edges[i][0]][edges[i][1]] = graph[edges[i][1]][edges[i][0]] = 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `    int seen[9] = {0}, order[9], length = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `    dfs(0, graph, seen, order, &length);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `    memset(seen, 0, sizeof seen);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `    int queue[9], head = 0, tail = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `    queue[tail++] = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `    seen[0] = 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `    while (head < tail) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `        int v = queue[head++];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `        printf(" %d", v);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `        for (int w = 0; w < 9; w++)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `            if (graph[v][w] && !seen[w]) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `                seen[w] = 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `                queue[tail++] = w;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `            }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L41: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L43: `    memset(seen, 0, sizeof seen);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `    int components[9][9], sizes[9], count = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `    for (int v = 0; v < 9; v++)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `        if (!seen[v]) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L47: `            sizes[count] = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `            dfs(v, graph, seen, components[count], &sizes[count]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `            qsort(components[count], sizes[count], sizeof(int), compare);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L50: `            count++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **751 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 739 tokens. The contiguous original span L5–L50 costs 844 tokens; the complete original source costs 1012 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L5: 711 tokens; removes `void dfs(int v, int graph[9][9], int *seen, int *order, int *length) {` from the dependency chain described above.
- Without L6: 740 tokens; removes `seen[v] = 1;` from the dependency chain described above.
- Without L7: 736 tokens; removes `order[(*length)++] = v;` from the dependency chain described above.
- Without L8: 727 tokens; removes `for (int w = 0; w < 9; w++)` from the dependency chain described above.
- Without L9: 729 tokens; removes `if (graph[v][w] && !seen[w])` from the dependency chain described above.
- Without L10: 730 tokens; removes `dfs(w, graph, seen, order, length);` from the dependency chain described above.
- Without L11: 749 tokens; removes `}` from the dependency chain described above.
- Without L13: 729 tokens; removes `int compare(const void *a, const void *b) {` from the dependency chain described above.
- Without L14: 725 tokens; removes `return *(const int *)a - *(const int *)b;` from the dependency chain described above.
- Without L15: 749 tokens; removes `}` from the dependency chain described above.
- Without L18: 731 tokens; removes `int graph[9][9] = {{0}};` from the dependency chain described above.
- Without L19: 666 tokens; removes `int edges[][2] = {{5, 0}, {3, 8}, {7, 2}, {1, 6}, {0, 2}, {5, 3}, {7, 5}, {6, 4}, {8, 7}};` from the dependency chain described above.
- Without L20: 727 tokens; removes `for (int i = 0; i < 9; i++)` from the dependency chain described above.
- Without L21: 706 tokens; removes `graph[edges[i][0]][edges[i][1]] = graph[edges[i][1]][edges[i][0]] = 1;` from the dependency chain described above.
- Without L22: 723 tokens; removes `int seen[9] = {0}, order[9], length = 0;` from the dependency chain described above.
- Without L23: 731 tokens; removes `dfs(0, graph, seen, order, &length);` from the dependency chain described above.
- Without L28: 736 tokens; removes `memset(seen, 0, sizeof seen);` from the dependency chain described above.
- Without L29: 728 tokens; removes `int queue[9], head = 0, tail = 0;` from the dependency chain described above.
- Without L30: 739 tokens; removes `queue[tail++] = 0;` from the dependency chain described above.
- Without L31: 740 tokens; removes `seen[0] = 1;` from the dependency chain described above.
- Without L33: 738 tokens; removes `while (head < tail) {` from the dependency chain described above.
- Without L34: 736 tokens; removes `int v = queue[head++];` from the dependency chain described above.
- Without L35: 736 tokens; removes `printf(" %d", v);` from the dependency chain described above.
- Without L36: 726 tokens; removes `for (int w = 0; w < 9; w++)` from the dependency chain described above.
- Without L37: 726 tokens; removes `if (graph[v][w] && !seen[w]) {` from the dependency chain described above.
- Without L38: 737 tokens; removes `seen[w] = 1;` from the dependency chain described above.
- Without L39: 736 tokens; removes `queue[tail++] = w;` from the dependency chain described above.
- Without L40: 746 tokens; removes `}` from the dependency chain described above.
- Without L41: 748 tokens; removes `}` from the dependency chain described above.
- Without L43: 736 tokens; removes `memset(seen, 0, sizeof seen);` from the dependency chain described above.
- Without L44: 726 tokens; removes `int components[9][9], sizes[9], count = 0;` from the dependency chain described above.
- Without L45: 727 tokens; removes `for (int v = 0; v < 9; v++)` from the dependency chain described above.
- Without L46: 737 tokens; removes `if (!seen[v]) {` from the dependency chain described above.
- Without L47: 738 tokens; removes `sizes[count] = 0;` from the dependency chain described above.
- Without L48: 723 tokens; removes `dfs(v, graph, seen, components[count], &sizes[count]);` from the dependency chain described above.
- Without L49: 724 tokens; removes `qsort(components[count], sizes[count], sizeof(int), compare);` from the dependency chain described above.
- Without L50: 744 tokens; removes `count++;` from the dependency chain described above.
