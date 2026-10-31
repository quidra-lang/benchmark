# Task B selection: 80_graph_traversal / PHP

## Common answer requirements

Explain DFS versus FIFO BFS over component 0; trace first reach of vertex 7 and visit-mark timing; explain component coverage for omitted vertices independently of visit order.

## Answer and source dependencies

Ascending neighbors give DFS 0,2,7,5,3,8: recursive DFS marks 7 on entry after edge 2→7, before exploring its neighbors. FIFO BFS gives 0,2,5,7,3,8: processing 0 enqueues 2 and 5; processing 2 first discovers/enqueues 7 and immediately marks it, so the edge from 5 does not enqueue it again. Both visit component {0,2,3,5,7,8}. The component pass uses fresh visited state, scans every vertex 0 through 8, starts a traversal at each unseen vertex and sorts each resulting membership list (or collects newly visited indices). Thus {1,4,6} is still recorded as the second component. Recursion versus queue scheduling changes order without changing reachability.



## Scope and dependency evidence checked after independent review

The DFS helper and graph-building loops must finish before traversal calls. BFS visit-at-enqueue happens within the neighbor guard, and the neighbor/queue loops finish before visited is cleared for the independent component pass. Empty order/component collections establish fresh result accumulation. These boundaries and initial states support DFS0,2,7,5,3,8, BFS0,2,5,7,3,8, first discovery of7 from2, and the separate component{1,4,6}.

Source: `main.php`. Selected original locations: L3,L4,L5,L6,L7,L8,L9,L10,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L24,L25,L26,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L42,L43,L44,L45,L46,L47,L48,L49.

- L3: `$adjacency = array_fill(0, 9, []);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `foreach ([[5, 0], [3, 8], [7, 2], [1, 6], [0, 2], [5, 3], [7, 5], [6, 4], [8, 7]] as [$a, $b]) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `    $adjacency[$a][] = $b;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `    $adjacency[$b][] = $a;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L8: `foreach ($adjacency as &$neighbors) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `    sort($neighbors, SORT_NUMERIC);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L13: `function dfs(int $vertex, array $adjacency, array &$seen, array &$order): void` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `{` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L15: `    $seen[$vertex] = true;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `    $order[] = $vertex;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    foreach ($adjacency[$vertex] as $neighbor) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `        if (!$seen[$neighbor]) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `            dfs($neighbor, $adjacency, $seen, $order);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L21: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L22: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L24: `$seen = array_fill(0, 9, false);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `$order = [];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `dfs(0, $adjacency, $seen, $order);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `$seen = array_fill(0, 9, false);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `$seen[0] = true;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `$queue = [0];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `$head = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `while ($head < count($queue)) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `    $vertex = $queue[$head++];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `    foreach ($adjacency[$vertex] as $neighbor) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `        if (!$seen[$neighbor]) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `            $seen[$neighbor] = true;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `            $queue[] = $neighbor;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L39: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L40: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L42: `$seen = array_fill(0, 9, false);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L43: `$components = [];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `for ($vertex = 0; $vertex < 9; $vertex++) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `    if (!$seen[$vertex]) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `        $component = [];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L47: `        dfs($vertex, $adjacency, $seen, $component);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `        sort($component, SORT_NUMERIC);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `        $components[] = $component;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **616 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 584 tokens. The contiguous original span L3–L49 costs 679 tokens; the complete original source costs 768 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L3: 597 tokens; removes `$adjacency = array_fill(0, 9, []);` from the dependency chain described above.
- Without L4: 528 tokens; removes `foreach ([[5, 0], [3, 8], [7, 2], [1, 6], [0, 2], [5, 3], [7, 5], [6, 4], [8, 7]] as [$a, $b]) {` from the dependency chain described above.
- Without L5: 601 tokens; removes `$adjacency[$a][] = $b;` from the dependency chain described above.
- Without L6: 601 tokens; removes `$adjacency[$b][] = $a;` from the dependency chain described above.
- Without L7: 614 tokens; removes `}` from the dependency chain described above.
- Without L8: 601 tokens; removes `foreach ($adjacency as &$neighbors) {` from the dependency chain described above.
- Without L9: 603 tokens; removes `sort($neighbors, SORT_NUMERIC);` from the dependency chain described above.
- Without L10: 614 tokens; removes `}` from the dependency chain described above.
- Without L13: 583 tokens; removes `function dfs(int $vertex, array $adjacency, array &$seen, array &$order): void` from the dependency chain described above.
- Without L14: 614 tokens; removes `{` from the dependency chain described above.
- Without L15: 603 tokens; removes `$seen[$vertex] = true;` from the dependency chain described above.
- Without L16: 605 tokens; removes `$order[] = $vertex;` from the dependency chain described above.
- Without L17: 597 tokens; removes `foreach ($adjacency[$vertex] as $neighbor) {` from the dependency chain described above.
- Without L18: 600 tokens; removes `if (!$seen[$neighbor]) {` from the dependency chain described above.
- Without L19: 594 tokens; removes `dfs($neighbor, $adjacency, $seen, $order);` from the dependency chain described above.
- Without L20: 612 tokens; removes `}` from the dependency chain described above.
- Without L21: 613 tokens; removes `}` from the dependency chain described above.
- Without L22: 614 tokens; removes `}` from the dependency chain described above.
- Without L24: 597 tokens; removes `$seen = array_fill(0, 9, false);` from the dependency chain described above.
- Without L25: 608 tokens; removes `$order = [];` from the dependency chain described above.
- Without L26: 598 tokens; removes `dfs(0, $adjacency, $seen, $order);` from the dependency chain described above.
- Without L28: 597 tokens; removes `$seen = array_fill(0, 9, false);` from the dependency chain described above.
- Without L29: 605 tokens; removes `$seen[0] = true;` from the dependency chain described above.
- Without L30: 606 tokens; removes `$queue = [0];` from the dependency chain described above.
- Without L31: 608 tokens; removes `$head = 0;` from the dependency chain described above.
- Without L32: 599 tokens; removes `while ($head < count($queue)) {` from the dependency chain described above.
- Without L33: 601 tokens; removes `$vertex = $queue[$head++];` from the dependency chain described above.
- Without L34: 597 tokens; removes `foreach ($adjacency[$vertex] as $neighbor) {` from the dependency chain described above.
- Without L35: 600 tokens; removes `if (!$seen[$neighbor]) {` from the dependency chain described above.
- Without L36: 601 tokens; removes `$seen[$neighbor] = true;` from the dependency chain described above.
- Without L37: 603 tokens; removes `$queue[] = $neighbor;` from the dependency chain described above.
- Without L38: 612 tokens; removes `}` from the dependency chain described above.
- Without L39: 613 tokens; removes `}` from the dependency chain described above.
- Without L40: 614 tokens; removes `}` from the dependency chain described above.
- Without L42: 597 tokens; removes `$seen = array_fill(0, 9, false);` from the dependency chain described above.
- Without L43: 608 tokens; removes `$components = [];` from the dependency chain described above.
- Without L44: 590 tokens; removes `for ($vertex = 0; $vertex < 9; $vertex++) {` from the dependency chain described above.
- Without L45: 601 tokens; removes `if (!$seen[$vertex]) {` from the dependency chain described above.
- Without L46: 606 tokens; removes `$component = [];` from the dependency chain described above.
- Without L47: 595 tokens; removes `dfs($vertex, $adjacency, $seen, $component);` from the dependency chain described above.
- Without L48: 602 tokens; removes `sort($component, SORT_NUMERIC);` from the dependency chain described above.
- Without L49: 604 tokens; removes `$components[] = $component;` from the dependency chain described above.
