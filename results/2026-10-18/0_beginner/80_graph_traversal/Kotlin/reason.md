# Task B selection: 80_graph_traversal / Kotlin

## Common answer requirements

Explain DFS versus FIFO BFS over component 0; trace first reach of vertex 7 and visit-mark timing; explain component coverage for omitted vertices independently of visit order.

## Answer and source dependencies

Ascending neighbors give DFS 0,2,7,5,3,8: recursive DFS marks 7 on entry after edge 2→7, before exploring its neighbors. FIFO BFS gives 0,2,5,7,3,8: processing 0 enqueues 2 and 5; processing 2 first discovers/enqueues 7 and immediately marks it, so the edge from 5 does not enqueue it again. Both visit component {0,2,3,5,7,8}. The component pass uses fresh visited state, scans every vertex 0 through 8, starts a traversal at each unseen vertex and sorts each resulting membership list (or collects newly visited indices). Thus {1,4,6} is still recorded as the second component. Recursion versus queue scheduling changes order without changing reachability.



## Scope and dependency evidence checked after independent review

The DFS helper and graph-building loops must finish before traversal calls. BFS visit-at-enqueue happens within the neighbor guard, and the neighbor/queue loops finish before visited is cleared for the independent component pass. Empty order/component collections establish fresh result accumulation. These boundaries and initial states support DFS0,2,7,5,3,8, BFS0,2,5,7,3,8, first discovery of7 from2, and the separate component{1,4,6}.

Source: `main.kt`. Selected original locations: L1,L2,L3,L4,L5,L6,L7,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39.

- L1: `fun dfs(v: Int, graph: Array<BooleanArray>, seen: BooleanArray, order: MutableList<Int>) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `    seen[v] = true` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `    order.add(v)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `    for (w in graph.indices) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `        if (graph[v][w] && !seen[w]) dfs(w, graph, seen, order)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L7: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L10: `    val graph = Array(9) { BooleanArray(9) }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    val edges = listOf(5 to 0, 3 to 8, 7 to 2, 1 to 6, 0 to 2, 5 to 3, 7 to 5, 6 to 4, 8 to 7)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    for ((a, b) in edges) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `        graph[a][b] = true` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `        graph[b][a] = true` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L16: `    val depth = mutableListOf<Int>()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    dfs(0, graph, BooleanArray(9), depth)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `    val seen = BooleanArray(9)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `    val queue = ArrayDeque<Int>()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `    val breadth = mutableListOf<Int>()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `    seen[0] = true` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `    queue.addLast(0)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `    while (queue.isNotEmpty()) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `        val v = queue.removeFirst()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `        breadth.add(v)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `        for (w in 0 until 9) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `            if (graph[v][w] && !seen[w]) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `                seen[w] = true` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `                queue.addLast(w)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `            }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L31: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L32: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L33: `    val components = mutableListOf<List<Int>>()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `    seen.fill(false)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `    for (v in 0 until 9) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `        if (!seen[v]) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `            val component = mutableListOf<Int>()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `            dfs(v, graph, seen, component)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `            components.add(component.sorted())` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **579 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 525 tokens. The contiguous original span L1–L39 costs 588 tokens; the complete original source costs 710 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 541 tokens; removes `fun dfs(v: Int, graph: Array<BooleanArray>, seen: BooleanArray, order: MutableList<Int>) {` from the dependency chain described above.
- Without L2: 569 tokens; removes `seen[v] = true` from the dependency chain described above.
- Without L3: 571 tokens; removes `order.add(v)` from the dependency chain described above.
- Without L4: 564 tokens; removes `for (w in graph.indices) {` from the dependency chain described above.
- Without L5: 543 tokens; removes `if (graph[v][w] && !seen[w]) dfs(w, graph, seen, order)` from the dependency chain described above.
- Without L6: 576 tokens; removes `}` from the dependency chain described above.
- Without L7: 577 tokens; removes `}` from the dependency chain described above.
- Without L10: 557 tokens; removes `val graph = Array(9) { BooleanArray(9) }` from the dependency chain described above.
- Without L11: 506 tokens; removes `val edges = listOf(5 to 0, 3 to 8, 7 to 2, 1 to 6, 0 to 2, 5 to 3, 7 to 5, 6 to 4, 8 to 7)` from the dependency chain described above.
- Without L12: 561 tokens; removes `for ((a, b) in edges) {` from the dependency chain described above.
- Without L13: 565 tokens; removes `graph[a][b] = true` from the dependency chain described above.
- Without L14: 565 tokens; removes `graph[b][a] = true` from the dependency chain described above.
- Without L15: 576 tokens; removes `}` from the dependency chain described above.
- Without L16: 563 tokens; removes `val depth = mutableListOf<Int>()` from the dependency chain described above.
- Without L17: 560 tokens; removes `dfs(0, graph, BooleanArray(9), depth)` from the dependency chain described above.
- Without L18: 566 tokens; removes `val seen = BooleanArray(9)` from the dependency chain described above.
- Without L19: 564 tokens; removes `val queue = ArrayDeque<Int>()` from the dependency chain described above.
- Without L20: 563 tokens; removes `val breadth = mutableListOf<Int>()` from the dependency chain described above.
- Without L21: 569 tokens; removes `seen[0] = true` from the dependency chain described above.
- Without L22: 570 tokens; removes `queue.addLast(0)` from the dependency chain described above.
- Without L23: 564 tokens; removes `while (queue.isNotEmpty()) {` from the dependency chain described above.
- Without L24: 564 tokens; removes `val v = queue.removeFirst()` from the dependency chain described above.
- Without L25: 570 tokens; removes `breadth.add(v)` from the dependency chain described above.
- Without L26: 561 tokens; removes `for (w in 0 until 9) {` from the dependency chain described above.
- Without L27: 554 tokens; removes `if (graph[v][w] && !seen[w]) {` from the dependency chain described above.
- Without L28: 566 tokens; removes `seen[w] = true` from the dependency chain described above.
- Without L29: 567 tokens; removes `queue.addLast(w)` from the dependency chain described above.
- Without L30: 574 tokens; removes `}` from the dependency chain described above.
- Without L31: 575 tokens; removes `}` from the dependency chain described above.
- Without L32: 576 tokens; removes `}` from the dependency chain described above.
- Without L33: 561 tokens; removes `val components = mutableListOf<List<Int>>()` from the dependency chain described above.
- Without L34: 571 tokens; removes `seen.fill(false)` from the dependency chain described above.
- Without L35: 562 tokens; removes `for (v in 0 until 9) {` from the dependency chain described above.
- Without L36: 565 tokens; removes `if (!seen[v]) {` from the dependency chain described above.
- Without L37: 561 tokens; removes `val component = mutableListOf<Int>()` from the dependency chain described above.
- Without L38: 562 tokens; removes `dfs(v, graph, seen, component)` from the dependency chain described above.
- Without L39: 565 tokens; removes `components.add(component.sorted())` from the dependency chain described above.
