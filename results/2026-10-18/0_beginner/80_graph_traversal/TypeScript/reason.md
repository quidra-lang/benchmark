# Task B selection: 80_graph_traversal / TypeScript

## Common answer requirements

Explain DFS versus FIFO BFS over component 0; trace first reach of vertex 7 and visit-mark timing; explain component coverage for omitted vertices independently of visit order.

## Answer and source dependencies

Ascending neighbors give DFS 0,2,7,5,3,8: recursive DFS marks 7 on entry after edge 2→7, before exploring its neighbors. FIFO BFS gives 0,2,5,7,3,8: processing 0 enqueues 2 and 5; processing 2 first discovers/enqueues 7 and immediately marks it, so the edge from 5 does not enqueue it again. Both visit component {0,2,3,5,7,8}. The component pass uses fresh visited state, scans every vertex 0 through 8, starts a traversal at each unseen vertex and sorts each resulting membership list (or collects newly visited indices). Thus {1,4,6} is still recorded as the second component. Recursion versus queue scheduling changes order without changing reachability.



## Scope and dependency evidence checked after independent review

The DFS helper and graph-building loops must finish before traversal calls. BFS visit-at-enqueue happens within the neighbor guard, and the neighbor/queue loops finish before visited is cleared for the independent component pass. Empty order/component collections establish fresh result accumulation. These boundaries and initial states support DFS0,2,7,5,3,8, BFS0,2,5,7,3,8, first discovery of7 from2, and the separate component{1,4,6}.

Source: `main.ts`. Selected original locations: L1,L2,L3,L4,L5,L6,L7,L9,L10,L11,L12,L13,L14,L15,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37.

- L1: `const edges = [[5, 0], [3, 8], [7, 2], [1, 6], [0, 2], [5, 3], [7, 5], [6, 4], [8, 7]];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `const graph: number[][] = Array.from({length: 9}, () => []);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `for (const [a, b] of edges) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `  graph[a].push(b);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `  graph[b].push(a);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L7: `for (const neighbors of graph) neighbors.sort((a, b) => a - b);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `function dfs(vertex: number, seen: Set<number>, order: number[]): void {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `  seen.add(vertex);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `  order.push(vertex);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `  for (const neighbor of graph[vertex]) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    if (!seen.has(neighbor)) dfs(neighbor, seen, order);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `  }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L15: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L17: `const depth: number[] = [];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `dfs(0, new Set(), depth);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `const queue = [0], breadth: number[] = [];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `const reached = new Set([0]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `for (let head = 0; head < queue.length; head++) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `  const vertex = queue[head];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `  breadth.push(vertex);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `  for (const neighbor of graph[vertex]) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `    if (!reached.has(neighbor)) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `      reached.add(neighbor);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `      queue.push(neighbor);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L29: `  }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L30: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L31: `const components: number[][] = [];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `const seen = new Set<number>();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `for (let vertex = 0; vertex < 9; vertex++) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `  if (!seen.has(vertex)) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `    const component: number[] = [];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `    dfs(vertex, seen, component);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `    components.push(component.sort((a, b) => a - b));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **584 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 556 tokens. The contiguous original span L1–L37 costs 586 tokens; the complete original source costs 701 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 506 tokens; removes `const edges = [[5, 0], [3, 8], [7, 2], [1, 6], [0, 2], [5, 3], [7, 5], [6, 4], [8, 7]];` from the dependency chain described above.
- Without L2: 552 tokens; removes `const graph: number[][] = Array.from({length: 9}, () => []);` from the dependency chain described above.
- Without L3: 565 tokens; removes `for (const [a, b] of edges) {` from the dependency chain described above.
- Without L4: 573 tokens; removes `graph[a].push(b);` from the dependency chain described above.
- Without L5: 573 tokens; removes `graph[b].push(a);` from the dependency chain described above.
- Without L6: 582 tokens; removes `}` from the dependency chain described above.
- Without L7: 551 tokens; removes `for (const neighbors of graph) neighbors.sort((a, b) => a - b);` from the dependency chain described above.
- Without L9: 553 tokens; removes `function dfs(vertex: number, seen: Set<number>, order: number[]): void {` from the dependency chain described above.
- Without L10: 575 tokens; removes `seen.add(vertex);` from the dependency chain described above.
- Without L11: 575 tokens; removes `order.push(vertex);` from the dependency chain described above.
- Without L12: 566 tokens; removes `for (const neighbor of graph[vertex]) {` from the dependency chain described above.
- Without L13: 559 tokens; removes `if (!seen.has(neighbor)) dfs(neighbor, seen, order);` from the dependency chain described above.
- Without L14: 581 tokens; removes `}` from the dependency chain described above.
- Without L15: 582 tokens; removes `}` from the dependency chain described above.
- Without L17: 571 tokens; removes `const depth: number[] = [];` from the dependency chain described above.
- Without L18: 568 tokens; removes `dfs(0, new Set(), depth);` from the dependency chain described above.
- Without L19: 562 tokens; removes `const queue = [0], breadth: number[] = [];` from the dependency chain described above.
- Without L20: 568 tokens; removes `const reached = new Set([0]);` from the dependency chain described above.
- Without L21: 557 tokens; removes `for (let head = 0; head < queue.length; head++) {` from the dependency chain described above.
- Without L22: 571 tokens; removes `const vertex = queue[head];` from the dependency chain described above.
- Without L23: 575 tokens; removes `breadth.push(vertex);` from the dependency chain described above.
- Without L24: 566 tokens; removes `for (const neighbor of graph[vertex]) {` from the dependency chain described above.
- Without L25: 569 tokens; removes `if (!reached.has(neighbor)) {` from the dependency chain described above.
- Without L26: 574 tokens; removes `reached.add(neighbor);` from the dependency chain described above.
- Without L27: 574 tokens; removes `queue.push(neighbor);` from the dependency chain described above.
- Without L28: 581 tokens; removes `}` from the dependency chain described above.
- Without L29: 581 tokens; removes `}` from the dependency chain described above.
- Without L30: 582 tokens; removes `}` from the dependency chain described above.
- Without L31: 570 tokens; removes `const components: number[][] = [];` from the dependency chain described above.
- Without L32: 568 tokens; removes `const seen = new Set<number>();` from the dependency chain described above.
- Without L33: 559 tokens; removes `for (let vertex = 0; vertex < 9; vertex++) {` from the dependency chain described above.
- Without L34: 569 tokens; removes `if (!seen.has(vertex)) {` from the dependency chain described above.
- Without L35: 570 tokens; removes `const component: number[] = [];` from the dependency chain described above.
- Without L36: 571 tokens; removes `dfs(vertex, seen, component);` from the dependency chain described above.
- Without L37: 557 tokens; removes `components.push(component.sort((a, b) => a - b));` from the dependency chain described above.
