# Task B selection: 80_graph_traversal / Zig

## Common answer requirements

Explain DFS versus FIFO BFS over component 0; trace first reach of vertex 7 and visit-mark timing; explain component coverage for omitted vertices independently of visit order.

## Answer and source dependencies

Ascending neighbors give DFS 0,2,7,5,3,8: recursive DFS marks 7 on entry after edge 2→7, before exploring its neighbors. FIFO BFS gives 0,2,5,7,3,8: processing 0 enqueues 2 and 5; processing 2 first discovers/enqueues 7 and immediately marks it, so the edge from 5 does not enqueue it again. Both visit component {0,2,3,5,7,8}. The component pass uses fresh visited state, scans every vertex 0 through 8, starts a traversal at each unseen vertex and sorts each resulting membership list (or collects newly visited indices). Thus {1,4,6} is still recorded as the second component. Recursion versus queue scheduling changes order without changing reachability.



## Scope and dependency evidence checked after independent review

The DFS helper and graph-building loops must finish before traversal calls. BFS visit-at-enqueue happens within the neighbor guard, and the neighbor/queue loops finish before visited is cleared for the independent component pass. Empty order/component collections establish fresh result accumulation. These boundaries and initial states support DFS0,2,7,5,3,8, BFS0,2,5,7,3,8, first discovery of7 from2, and the separate component{1,4,6}.

Source: `main.zig`. Selected original locations: L3,L4,L5,L6,L7,L8,L9,L10,L11,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L28,L29,L34,L35,L36,L37,L38,L39,L40,L41,L42,L44,L45,L46,L47,L48,L49,L50,L51,L52,L55,L56,L57,L58,L59,L60,L61,L62.

- L3: `fn dfs(graph: *const [9][9]bool, v: usize, visited: *[9]bool, order: *[9]usize, len: *usize) void {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `    visited[v] = true;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `    order[len.*] = v;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `    len.* += 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `    for (0..9) |u| {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `        if (graph[v][u] and !visited[u])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `            dfs(graph, u, visited, order, len);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L11: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L17: `    var graph: [9][9]bool = @splat(@splat(false));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `    const edges = [_][2]usize{` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `        .{ 5, 0 }, .{ 3, 8 }, .{ 7, 2 }, .{ 1, 6 }, .{ 0, 2 },` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `        .{ 5, 3 }, .{ 7, 5 }, .{ 6, 4 }, .{ 8, 7 },` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `    };` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L22: `    for (edges) |e| {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `        graph[e[0]][e[1]] = true;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `        graph[e[1]][e[0]] = true;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L26: `    var visited: [9]bool = @splat(false);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `    var len: usize = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `    dfs(&graph, 0, &visited, &order, &len);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `    visited = @splat(false);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `    var queue: [9]usize = undefined;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `    queue[0] = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `    var head: usize = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `    var tail: usize = 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `    visited[0] = true;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `    while (head < tail) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `        const v = queue[head];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `        head += 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `        for (0..9) |u| {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `            if (graph[v][u] and !visited[u]) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `                visited[u] = true;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L47: `                queue[tail] = u;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `                tail += 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `            }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L50: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L51: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L52: `    visited = @splat(false);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L55: `    var count: usize = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L56: `    for (0..9) |v| {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L57: `        if (!visited[v]) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L58: `            len = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L59: `            dfs(&graph, v, &visited, &components[count], &len);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L60: `            sizes[count] = len;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L61: `            std.mem.sort(usize, components[count][0..len], {}, std.sort.asc(usize));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L62: `            count += 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **767 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 743 tokens. The contiguous original span L3–L62 costs 1000 tokens; the complete original source costs 1170 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L3: 712 tokens; removes `fn dfs(graph: *const [9][9]bool, v: usize, visited: *[9]bool, order: *[9]usize, len: *usize) void {` from the dependency chain described above.
- Without L4: 756 tokens; removes `visited[v] = true;` from the dependency chain described above.
- Without L5: 755 tokens; removes `order[len.*] = v;` from the dependency chain described above.
- Without L6: 758 tokens; removes `len.* += 1;` from the dependency chain described above.
- Without L7: 752 tokens; removes `for (0..9) |u| {` from the dependency chain described above.
- Without L8: 745 tokens; removes `if (graph[v][u] and !visited[u])` from the dependency chain described above.
- Without L9: 746 tokens; removes `dfs(graph, u, visited, order, len);` from the dependency chain described above.
- Without L10: 764 tokens; removes `}` from the dependency chain described above.
- Without L11: 765 tokens; removes `}` from the dependency chain described above.
- Without L17: 740 tokens; removes `var graph: [9][9]bool = @splat(@splat(false));` from the dependency chain described above.
- Without L18: 751 tokens; removes `const edges = [_][2]usize{` from the dependency chain described above.
- Without L19: 710 tokens; removes `.{ 5, 0 }, .{ 3, 8 }, .{ 7, 2 }, .{ 1, 6 }, .{ 0, 2 },` from the dependency chain described above.
- Without L20: 721 tokens; removes `.{ 5, 3 }, .{ 7, 5 }, .{ 6, 4 }, .{ 8, 7 },` from the dependency chain described above.
- Without L21: 763 tokens; removes `};` from the dependency chain described above.
- Without L22: 754 tokens; removes `for (edges) |e| {` from the dependency chain described above.
- Without L23: 748 tokens; removes `graph[e[0]][e[1]] = true;` from the dependency chain described above.
- Without L24: 748 tokens; removes `graph[e[1]][e[0]] = true;` from the dependency chain described above.
- Without L25: 764 tokens; removes `}` from the dependency chain described above.
- Without L26: 747 tokens; removes `var visited: [9]bool = @splat(false);` from the dependency chain described above.
- Without L28: 754 tokens; removes `var len: usize = 0;` from the dependency chain described above.
- Without L29: 744 tokens; removes `dfs(&graph, 0, &visited, &order, &len);` from the dependency chain described above.
- Without L34: 755 tokens; removes `visited = @splat(false);` from the dependency chain described above.
- Without L35: 751 tokens; removes `var queue: [9]usize = undefined;` from the dependency chain described above.
- Without L36: 756 tokens; removes `queue[0] = 0;` from the dependency chain described above.
- Without L37: 754 tokens; removes `var head: usize = 0;` from the dependency chain described above.
- Without L38: 754 tokens; removes `var tail: usize = 1;` from the dependency chain described above.
- Without L39: 756 tokens; removes `visited[0] = true;` from the dependency chain described above.
- Without L40: 754 tokens; removes `while (head < tail) {` from the dependency chain described above.
- Without L41: 753 tokens; removes `const v = queue[head];` from the dependency chain described above.
- Without L42: 758 tokens; removes `head += 1;` from the dependency chain described above.
- Without L44: 751 tokens; removes `for (0..9) |u| {` from the dependency chain described above.
- Without L45: 742 tokens; removes `if (graph[v][u] and !visited[u]) {` from the dependency chain described above.
- Without L46: 753 tokens; removes `visited[u] = true;` from the dependency chain described above.
- Without L47: 753 tokens; removes `queue[tail] = u;` from the dependency chain described above.
- Without L48: 756 tokens; removes `tail += 1;` from the dependency chain described above.
- Without L49: 762 tokens; removes `}` from the dependency chain described above.
- Without L50: 763 tokens; removes `}` from the dependency chain described above.
- Without L51: 764 tokens; removes `}` from the dependency chain described above.
- Without L52: 755 tokens; removes `visited = @splat(false);` from the dependency chain described above.
- Without L55: 754 tokens; removes `var count: usize = 0;` from the dependency chain described above.
- Without L56: 752 tokens; removes `for (0..9) |v| {` from the dependency chain described above.
- Without L57: 753 tokens; removes `if (!visited[v]) {` from the dependency chain described above.
- Without L58: 757 tokens; removes `len = 0;` from the dependency chain described above.
- Without L59: 739 tokens; removes `dfs(&graph, v, &visited, &components[count], &len);` from the dependency chain described above.
- Without L60: 754 tokens; removes `sizes[count] = len;` from the dependency chain described above.
- Without L61: 729 tokens; removes `std.mem.sort(usize, components[count][0..len], {}, std.sort.asc(usize));` from the dependency chain described above.
- Without L62: 757 tokens; removes `count += 1;` from the dependency chain described above.
