# Task B selection: 80_graph_traversal / Go

## Common answer requirements

Explain DFS versus FIFO BFS over component 0; trace first reach of vertex 7 and visit-mark timing; explain component coverage for omitted vertices independently of visit order.

## Answer and source dependencies

Ascending neighbors give DFS 0,2,7,5,3,8: recursive DFS marks 7 on entry after edge 2→7, before exploring its neighbors. FIFO BFS gives 0,2,5,7,3,8: processing 0 enqueues 2 and 5; processing 2 first discovers/enqueues 7 and immediately marks it, so the edge from 5 does not enqueue it again. Both visit component {0,2,3,5,7,8}. The component pass uses fresh visited state, scans every vertex 0 through 8, starts a traversal at each unseen vertex and sorts each resulting membership list (or collects newly visited indices). Thus {1,4,6} is still recorded as the second component. Recursion versus queue scheduling changes order without changing reachability.



## Scope and dependency evidence checked after independent review

The DFS helper and graph-building loops must finish before traversal calls. BFS visit-at-enqueue happens within the neighbor guard, and the neighbor/queue loops finish before visited is cleared for the independent component pass. Empty order/component collections establish fresh result accumulation. These boundaries and initial states support DFS0,2,7,5,3,8, BFS0,2,5,7,3,8, first discovery of7 from2, and the separate component{1,4,6}.

Source: `main.go`. Selected original locations: L8,L9,L10,L11,L12,L13,L14,L15,L16,L19,L20,L21,L22,L23,L24,L25,L31,L32,L33,L35,L36,L38,L39,L40,L41,L42,L43,L44,L46,L47,L48,L49,L50,L51,L52,L53.

- L8: `func dfs(v int, graph *[9][9]bool, seen *[9]bool, order *[]int) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `	seen[v] = true` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `	*order = append(*order, v)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `	for w := 0; w < 9; w++ {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `		if graph[v][w] && !seen[w] {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `			dfs(w, graph, seen, order)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `		}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L15: `	}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L16: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L19: `	graph := [9][9]bool{}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `	for _, e := range [][2]int{{5, 0}, {3, 8}, {7, 2}, {1, 6}, {0, 2}, {5, 3}, {7, 5}, {6, 4}, {8, 7}} {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `		graph[e[0]][e[1]], graph[e[1]][e[0]] = true, true` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `	}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L23: `	seen := [9]bool{}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `	order := []int{}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `	dfs(0, &graph, &seen, &order)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `	seen = [9]bool{}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `	queue := []int{0}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `	seen[0] = true` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `	for head := 0; head < len(queue); head++ {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `		v := queue[head]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `		for w := 0; w < 9; w++ {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `			if graph[v][w] && !seen[w] {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `				seen[w] = true` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `				queue = append(queue, w)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `			}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L43: `		}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L44: `	}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L46: `	seen = [9]bool{}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L47: `	components := [][]int{}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `	for v := 0; v < 9; v++ {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `		if !seen[v] {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L50: `			component := []int{}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L51: `			dfs(v, &graph, &seen, &component)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L52: `			sort.Ints(component)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L53: `			components = append(components, component)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **588 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 564 tokens. The contiguous original span L8–L53 costs 684 tokens; the complete original source costs 821 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L8: 549 tokens; removes `func dfs(v int, graph *[9][9]bool, seen *[9]bool, order *[]int) {` from the dependency chain described above.
- Without L9: 578 tokens; removes `seen[v] = true` from the dependency chain described above.
- Without L10: 573 tokens; removes `*order = append(*order, v)` from the dependency chain described above.
- Without L11: 566 tokens; removes `for w := 0; w < 9; w++ {` from the dependency chain described above.
- Without L12: 566 tokens; removes `if graph[v][w] && !seen[w] {` from the dependency chain described above.
- Without L13: 571 tokens; removes `dfs(w, graph, seen, order)` from the dependency chain described above.
- Without L14: 584 tokens; removes `}` from the dependency chain described above.
- Without L15: 585 tokens; removes `}` from the dependency chain described above.
- Without L16: 586 tokens; removes `}` from the dependency chain described above.
- Without L19: 573 tokens; removes `graph := [9][9]bool{}` from the dependency chain described above.
- Without L20: 496 tokens; removes `for _, e := range [][2]int{{5, 0}, {3, 8}, {7, 2}, {1, 6}, {0, 2}, {5, 3}, {7, 5}, {6, 4}, {8, 7}} {` from the dependency chain described above.
- Without L21: 554 tokens; removes `graph[e[0]][e[1]], graph[e[1]][e[0]] = true, true` from the dependency chain described above.
- Without L22: 585 tokens; removes `}` from the dependency chain described above.
- Without L23: 576 tokens; removes `seen := [9]bool{}` from the dependency chain described above.
- Without L24: 578 tokens; removes `order := []int{}` from the dependency chain described above.
- Without L25: 570 tokens; removes `dfs(0, &graph, &seen, &order)` from the dependency chain described above.
- Without L31: 576 tokens; removes `seen = [9]bool{}` from the dependency chain described above.
- Without L32: 577 tokens; removes `queue := []int{0}` from the dependency chain described above.
- Without L33: 578 tokens; removes `seen[0] = true` from the dependency chain described above.
- Without L35: 563 tokens; removes `for head := 0; head < len(queue); head++ {` from the dependency chain described above.
- Without L36: 577 tokens; removes `v := queue[head]` from the dependency chain described above.
- Without L38: 565 tokens; removes `for w := 0; w < 9; w++ {` from the dependency chain described above.
- Without L39: 565 tokens; removes `if graph[v][w] && !seen[w] {` from the dependency chain described above.
- Without L40: 575 tokens; removes `seen[w] = true` from the dependency chain described above.
- Without L41: 572 tokens; removes `queue = append(queue, w)` from the dependency chain described above.
- Without L42: 583 tokens; removes `}` from the dependency chain described above.
- Without L43: 584 tokens; removes `}` from the dependency chain described above.
- Without L44: 585 tokens; removes `}` from the dependency chain described above.
- Without L46: 576 tokens; removes `seen = [9]bool{}` from the dependency chain described above.
- Without L47: 577 tokens; removes `components := [][]int{}` from the dependency chain described above.
- Without L48: 566 tokens; removes `for v := 0; v < 9; v++ {` from the dependency chain described above.
- Without L49: 576 tokens; removes `if !seen[v] {` from the dependency chain described above.
- Without L50: 576 tokens; removes `component := []int{}` from the dependency chain described above.
- Without L51: 568 tokens; removes `dfs(v, &graph, &seen, &component)` from the dependency chain described above.
- Without L52: 578 tokens; removes `sort.Ints(component)` from the dependency chain described above.
- Without L53: 573 tokens; removes `components = append(components, component)` from the dependency chain described above.
