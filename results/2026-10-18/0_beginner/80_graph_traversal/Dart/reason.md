# Task B selection: 80_graph_traversal / Dart

## Common answer requirements

Explain DFS versus FIFO BFS over component 0; trace first reach of vertex 7 and visit-mark timing; explain component coverage for omitted vertices independently of visit order.

## Answer and source dependencies

Ascending neighbors give DFS 0,2,7,5,3,8: recursive DFS marks 7 on entry after edge 2→7, before exploring its neighbors. FIFO BFS gives 0,2,5,7,3,8: processing 0 enqueues 2 and 5; processing 2 first discovers/enqueues 7 and immediately marks it, so the edge from 5 does not enqueue it again. Both visit component {0,2,3,5,7,8}. The component pass uses fresh visited state, scans every vertex 0 through 8, starts a traversal at each unseen vertex and sorts each resulting membership list (or collects newly visited indices). Thus {1,4,6} is still recorded as the second component. Recursion versus queue scheduling changes order without changing reachability.



## Scope and dependency evidence checked after independent review

The DFS helper and graph-building loops must finish before traversal calls. BFS visit-at-enqueue happens within the neighbor guard, and the neighbor/queue loops finish before visited is cleared for the independent component pass. Empty order/component collections establish fresh result accumulation. These boundaries and initial states support DFS0,2,7,5,3,8, BFS0,2,5,7,3,8, first discovery of7 from2, and the separate component{1,4,6}.

Source: `main.dart`. Selected original locations: L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L30,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41,L42,L43,L45,L46,L47,L48,L49,L50,L51,L52.

- L2: `  final graph = List.generate(9, (_) => <int>[]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `  for (final e in [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `    (5, 0),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `    (3, 8),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `    (7, 2),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `    (1, 6),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `    (0, 2),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `    (5, 3),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    (7, 5),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    (6, 4),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    (8, 7),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `  ]) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    graph[e.$1].add(e.$2);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    graph[e.$2].add(e.$1);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `  }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L17: `  for (final list in graph) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `    list.sort();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `  }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L20: `  var visited = List.filled(9, false);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `  final order = <int>[];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `  void dfs(int v, List<int> result) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `    visited[v] = true;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `    result.add(v);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `    for (final u in graph[v]) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `      if (!visited[u]) dfs(u, result);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L28: `  }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L30: `  dfs(0, order);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `  visited = List.filled(9, false);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `  final queue = [0];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `  visited[0] = true;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `  for (var head = 0; head < queue.length; head++) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `    final v = queue[head];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `    for (final u in graph[v]) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `      if (!visited[u]) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `        visited[u] = true;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `        queue.add(u);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `      }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L42: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L43: `  }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L45: `  visited = List.filled(9, false);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `  final components = <List<int>>[];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L47: `  for (var v = 0; v < 9; v++) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `    if (!visited[v]) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `      final component = <int>[];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L50: `      dfs(v, component);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L51: `      component.sort();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L52: `      components.add(component);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **569 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 534 tokens. The contiguous original span L2–L52 costs 614 tokens; the complete original source costs 710 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L2: 542 tokens; removes `final graph = List.generate(9, (_) => <int>[]);` from the dependency chain described above.
- Without L3: 557 tokens; removes `for (final e in [` from the dependency chain described above.
- Without L4: 560 tokens; removes `(5, 0),` from the dependency chain described above.
- Without L5: 560 tokens; removes `(3, 8),` from the dependency chain described above.
- Without L6: 560 tokens; removes `(7, 2),` from the dependency chain described above.
- Without L7: 560 tokens; removes `(1, 6),` from the dependency chain described above.
- Without L8: 560 tokens; removes `(0, 2),` from the dependency chain described above.
- Without L9: 560 tokens; removes `(5, 3),` from the dependency chain described above.
- Without L10: 560 tokens; removes `(7, 5),` from the dependency chain described above.
- Without L11: 560 tokens; removes `(6, 4),` from the dependency chain described above.
- Without L12: 560 tokens; removes `(8, 7),` from the dependency chain described above.
- Without L13: 563 tokens; removes `]) {` from the dependency chain described above.
- Without L14: 554 tokens; removes `graph[e.$1].add(e.$2);` from the dependency chain described above.
- Without L15: 554 tokens; removes `graph[e.$2].add(e.$1);` from the dependency chain described above.
- Without L16: 566 tokens; removes `}` from the dependency chain described above.
- Without L17: 554 tokens; removes `for (final list in graph) {` from the dependency chain described above.
- Without L18: 561 tokens; removes `list.sort();` from the dependency chain described above.
- Without L19: 566 tokens; removes `}` from the dependency chain described above.
- Without L20: 551 tokens; removes `var visited = List.filled(9, false);` from the dependency chain described above.
- Without L21: 556 tokens; removes `final order = <int>[];` from the dependency chain described above.
- Without L22: 549 tokens; removes `void dfs(int v, List<int> result) {` from the dependency chain described above.
- Without L23: 558 tokens; removes `visited[v] = true;` from the dependency chain described above.
- Without L24: 560 tokens; removes `result.add(v);` from the dependency chain described above.
- Without L25: 551 tokens; removes `for (final u in graph[v]) {` from the dependency chain described above.
- Without L26: 548 tokens; removes `if (!visited[u]) dfs(u, result);` from the dependency chain described above.
- Without L27: 566 tokens; removes `}` from the dependency chain described above.
- Without L28: 566 tokens; removes `}` from the dependency chain described above.
- Without L30: 559 tokens; removes `dfs(0, order);` from the dependency chain described above.
- Without L32: 553 tokens; removes `visited = List.filled(9, false);` from the dependency chain described above.
- Without L33: 557 tokens; removes `final queue = [0];` from the dependency chain described above.
- Without L34: 558 tokens; removes `visited[0] = true;` from the dependency chain described above.
- Without L35: 541 tokens; removes `for (var head = 0; head < queue.length; head++) {` from the dependency chain described above.
- Without L36: 556 tokens; removes `final v = queue[head];` from the dependency chain described above.
- Without L37: 551 tokens; removes `for (final u in graph[v]) {` from the dependency chain described above.
- Without L38: 555 tokens; removes `if (!visited[u]) {` from the dependency chain described above.
- Without L39: 557 tokens; removes `visited[u] = true;` from the dependency chain described above.
- Without L40: 559 tokens; removes `queue.add(u);` from the dependency chain described above.
- Without L41: 565 tokens; removes `}` from the dependency chain described above.
- Without L42: 566 tokens; removes `}` from the dependency chain described above.
- Without L43: 566 tokens; removes `}` from the dependency chain described above.
- Without L45: 553 tokens; removes `visited = List.filled(9, false);` from the dependency chain described above.
- Without L46: 554 tokens; removes `final components = <List<int>>[];` from the dependency chain described above.
- Without L47: 543 tokens; removes `for (var v = 0; v < 9; v++) {` from the dependency chain described above.
- Without L48: 556 tokens; removes `if (!visited[v]) {` from the dependency chain described above.
- Without L49: 555 tokens; removes `final component = <int>[];` from the dependency chain described above.
- Without L50: 558 tokens; removes `dfs(v, component);` from the dependency chain described above.
- Without L51: 560 tokens; removes `component.sort();` from the dependency chain described above.
- Without L52: 559 tokens; removes `components.add(component);` from the dependency chain described above.
