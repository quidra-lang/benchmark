# Task B selection: 80_graph_traversal / Python

## Common answer requirements

Explain DFS versus FIFO BFS over component 0; trace first reach of vertex 7 and visit-mark timing; explain component coverage for omitted vertices independently of visit order.

## Answer and source dependencies

Ascending neighbors give DFS 0,2,7,5,3,8: recursive DFS marks 7 on entry after edge 2→7, before exploring its neighbors. FIFO BFS gives 0,2,5,7,3,8: processing 0 enqueues 2 and 5; processing 2 first discovers/enqueues 7 and immediately marks it, so the edge from 5 does not enqueue it again. Both visit component {0,2,3,5,7,8}. The component pass uses fresh visited state, scans every vertex 0 through 8, starts a traversal at each unseen vertex and sorts each resulting membership list (or collects newly visited indices). Thus {1,4,6} is still recorded as the second component. Recursion versus queue scheduling changes order without changing reachability.



## Scope and dependency evidence checked after independent review

The DFS helper and graph-building loops must finish before traversal calls. BFS visit-at-enqueue happens within the neighbor guard, and the neighbor/queue loops finish before visited is cleared for the independent component pass. Empty order/component collections establish fresh result accumulation. These boundaries and initial states support DFS0,2,7,5,3,8, BFS0,2,5,7,3,8, first discovery of7 from2, and the separate component{1,4,6}.

Source: `main.py`. Selected original locations: L3,L4,L5,L6,L7,L8,L9,L12,L13,L14,L15,L16,L17,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38.

- L3: `edges = [(5, 0), (3, 8), (7, 2), (1, 6), (0, 2), (5, 3), (7, 5), (6, 4), (8, 7)]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `graph = [[] for _ in range(9)]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `for a, b in edges:` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `    graph[a].append(b)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `    graph[b].append(a)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `for neighbors in graph:` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `    neighbors.sort()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `def dfs(vertex, seen, order):` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    seen.add(vertex)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    order.append(vertex)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    for neighbor in graph[vertex]:` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `        if neighbor not in seen:` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `            dfs(neighbor, seen, order)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `depth = []` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `dfs(0, set(), depth)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `queue = deque([0])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `seen = {0}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `breadth = []` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `while queue:` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `    vertex = queue.popleft()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `    breadth.append(vertex)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `    for neighbor in graph[vertex]:` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `        if neighbor not in seen:` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `            seen.add(neighbor)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `            queue.append(neighbor)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `components = []` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `seen = set()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `for vertex in range(9):` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `    if vertex not in seen:` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `        component = []` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `        dfs(vertex, seen, component)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `        components.append(sorted(component))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **397 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 385 tokens. The contiguous original span L3–L38 costs 401 tokens; the complete original source costs 485 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L3: 320 tokens; removes `edges = [(5, 0), (3, 8), (7, 2), (1, 6), (0, 2), (5, 3), (7, 5), (6, 4), (8, 7)]` from the dependency chain described above.
- Without L4: 378 tokens; removes `graph = [[] for _ in range(9)]` from the dependency chain described above.
- Without L5: 385 tokens; removes `for a, b in edges:` from the dependency chain described above.
- Without L6: 387 tokens; removes `graph[a].append(b)` from the dependency chain described above.
- Without L7: 387 tokens; removes `graph[b].append(a)` from the dependency chain described above.
- Without L8: 388 tokens; removes `for neighbors in graph:` from the dependency chain described above.
- Without L9: 390 tokens; removes `neighbors.sort()` from the dependency chain described above.
- Without L12: 383 tokens; removes `def dfs(vertex, seen, order):` from the dependency chain described above.
- Without L13: 389 tokens; removes `seen.add(vertex)` from the dependency chain described above.
- Without L14: 389 tokens; removes `order.append(vertex)` from the dependency chain described above.
- Without L15: 385 tokens; removes `for neighbor in graph[vertex]:` from the dependency chain described above.
- Without L16: 384 tokens; removes `if neighbor not in seen:` from the dependency chain described above.
- Without L17: 383 tokens; removes `dfs(neighbor, seen, order)` from the dependency chain described above.
- Without L20: 391 tokens; removes `depth = []` from the dependency chain described above.
- Without L21: 384 tokens; removes `dfs(0, set(), depth)` from the dependency chain described above.
- Without L22: 386 tokens; removes `queue = deque([0])` from the dependency chain described above.
- Without L23: 389 tokens; removes `seen = {0}` from the dependency chain described above.
- Without L24: 391 tokens; removes `breadth = []` from the dependency chain described above.
- Without L25: 392 tokens; removes `while queue:` from the dependency chain described above.
- Without L26: 386 tokens; removes `vertex = queue.popleft()` from the dependency chain described above.
- Without L27: 389 tokens; removes `breadth.append(vertex)` from the dependency chain described above.
- Without L28: 385 tokens; removes `for neighbor in graph[vertex]:` from the dependency chain described above.
- Without L29: 384 tokens; removes `if neighbor not in seen:` from the dependency chain described above.
- Without L30: 387 tokens; removes `seen.add(neighbor)` from the dependency chain described above.
- Without L31: 387 tokens; removes `queue.append(neighbor)` from the dependency chain described above.
- Without L32: 391 tokens; removes `components = []` from the dependency chain described above.
- Without L33: 389 tokens; removes `seen = set()` from the dependency chain described above.
- Without L34: 385 tokens; removes `for vertex in range(9):` from the dependency chain described above.
- Without L35: 385 tokens; removes `if vertex not in seen:` from the dependency chain described above.
- Without L36: 389 tokens; removes `component = []` from the dependency chain described above.
- Without L37: 384 tokens; removes `dfs(vertex, seen, component)` from the dependency chain described above.
- Without L38: 385 tokens; removes `components.append(sorted(component))` from the dependency chain described above.
