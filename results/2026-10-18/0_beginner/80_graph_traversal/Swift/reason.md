# Task B selection: 80_graph_traversal / Swift

## Common answer requirements

Explain DFS versus FIFO BFS over component 0; trace first reach of vertex 7 and visit-mark timing; explain component coverage for omitted vertices independently of visit order.

## Answer and source dependencies

Ascending neighbors give DFS 0,2,7,5,3,8: recursive DFS marks 7 on entry after edge 2→7, before exploring its neighbors. FIFO BFS gives 0,2,5,7,3,8: processing 0 enqueues 2 and 5; processing 2 first discovers/enqueues 7 and immediately marks it, so the edge from 5 does not enqueue it again. Both visit component {0,2,3,5,7,8}. The component pass uses fresh visited state, scans every vertex 0 through 8, starts a traversal at each unseen vertex and sorts each resulting membership list (or collects newly visited indices). Thus {1,4,6} is still recorded as the second component. Recursion versus queue scheduling changes order without changing reachability.



## Scope and dependency evidence checked after independent review

The DFS helper and graph-building loops must finish before traversal calls. BFS visit-at-enqueue happens within the neighbor guard, and the neighbor/queue loops finish before visited is cleared for the independent component pass. Empty order/component collections establish fresh result accumulation. These boundaries and initial states support DFS0,2,7,5,3,8, BFS0,2,5,7,3,8, first discovery of7 from2, and the separate component{1,4,6}.

Source: `main.swift`. Selected original locations: L1,L2,L3,L4,L5,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32.

- L1: `func dfs(_ v: Int, _ graph: [[Bool]], _ seen: inout [Bool], _ order: inout [Int]) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `    seen[v] = true` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `    order.append(v)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `    for w in graph.indices where graph[v][w] && !seen[w] { dfs(w, graph, &seen, &order) }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L7: `var graph = [[Bool]](repeating: [Bool](repeating: false, count: 9), count: 9)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `let edges = [(5, 0), (3, 8), (7, 2), (1, 6), (0, 2), (5, 3), (7, 5), (6, 4), (8, 7)]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `for (a, b) in edges {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    graph[a][b] = true` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    graph[b][a] = true` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L13: `var seen = [Bool](repeating: false, count: 9), depth = [Int]()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `dfs(0, graph, &seen, &depth)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `seen = [Bool](repeating: false, count: 9)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `var queue = [0], head = 0, breadth = [Int]()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `seen[0] = true` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `while head < queue.count {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `    let v = queue[head]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `    head += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `    breadth.append(v)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `    for w in 0..<9 where graph[v][w] && !seen[w] {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `        seen[w] = true` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `        queue.append(w)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L26: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L27: `var components = [[Int]]()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `seen = [Bool](repeating: false, count: 9)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `for v in 0..<9 where !seen[v] {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `    var component = [Int]()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `    dfs(v, graph, &seen, &component)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `    components.append(component.sorted())` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **569 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 548 tokens. The contiguous original span L1–L32 costs 570 tokens; the complete original source costs 708 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 522 tokens; removes `func dfs(_ v: Int, _ graph: [[Bool]], _ seen: inout [Bool], _ order: inout [Int]) {` from the dependency chain described above.
- Without L2: 559 tokens; removes `seen[v] = true` from the dependency chain described above.
- Without L3: 561 tokens; removes `order.append(v)` from the dependency chain described above.
- Without L4: 520 tokens; removes `for w in graph.indices where graph[v][w] && !seen[w] { dfs(w, graph, &seen, &order) }` from the dependency chain described above.
- Without L5: 567 tokens; removes `}` from the dependency chain described above.
- Without L7: 533 tokens; removes `var graph = [[Bool]](repeating: [Bool](repeating: false, count: 9), count: 9)` from the dependency chain described above.
- Without L8: 490 tokens; removes `let edges = [(5, 0), (3, 8), (7, 2), (1, 6), (0, 2), (5, 3), (7, 5), (6, 4), (8, 7)]` from the dependency chain described above.
- Without L9: 554 tokens; removes `for (a, b) in edges {` from the dependency chain described above.
- Without L10: 556 tokens; removes `graph[a][b] = true` from the dependency chain described above.
- Without L11: 556 tokens; removes `graph[b][a] = true` from the dependency chain described above.
- Without L12: 567 tokens; removes `}` from the dependency chain described above.
- Without L13: 536 tokens; removes `var seen = [Bool](repeating: false, count: 9), depth = [Int]()` from the dependency chain described above.
- Without L14: 553 tokens; removes `dfs(0, graph, &seen, &depth)` from the dependency chain described above.
- Without L15: 549 tokens; removes `seen = [Bool](repeating: false, count: 9)` from the dependency chain described above.
- Without L16: 541 tokens; removes `var queue = [0], head = 0, breadth = [Int]()` from the dependency chain described above.
- Without L17: 560 tokens; removes `seen[0] = true` from the dependency chain described above.
- Without L18: 557 tokens; removes `while head < queue.count {` from the dependency chain described above.
- Without L19: 557 tokens; removes `let v = queue[head]` from the dependency chain described above.
- Without L20: 562 tokens; removes `head += 1` from the dependency chain described above.
- Without L21: 561 tokens; removes `breadth.append(v)` from the dependency chain described above.
- Without L22: 538 tokens; removes `for w in 0..<9 where graph[v][w] && !seen[w] {` from the dependency chain described above.
- Without L23: 558 tokens; removes `seen[w] = true` from the dependency chain described above.
- Without L24: 560 tokens; removes `queue.append(w)` from the dependency chain described above.
- Without L25: 566 tokens; removes `}` from the dependency chain described above.
- Without L26: 567 tokens; removes `}` from the dependency chain described above.
- Without L27: 557 tokens; removes `var components = [[Int]]()` from the dependency chain described above.
- Without L28: 549 tokens; removes `seen = [Bool](repeating: false, count: 9)` from the dependency chain described above.
- Without L29: 549 tokens; removes `for v in 0..<9 where !seen[v] {` from the dependency chain described above.
- Without L30: 556 tokens; removes `var component = [Int]()` from the dependency chain described above.
- Without L31: 552 tokens; removes `dfs(v, graph, &seen, &component)` from the dependency chain described above.
- Without L32: 557 tokens; removes `components.append(component.sorted())` from the dependency chain described above.
