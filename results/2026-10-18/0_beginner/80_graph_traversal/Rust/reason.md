# Task B selection: 80_graph_traversal / Rust

## Common answer requirements

Explain DFS versus FIFO BFS over component 0; trace first reach of vertex 7 and visit-mark timing; explain component coverage for omitted vertices independently of visit order.

## Answer and source dependencies

Ascending neighbors give DFS 0,2,7,5,3,8: recursive DFS marks 7 on entry after edge 2→7, before exploring its neighbors. FIFO BFS gives 0,2,5,7,3,8: processing 0 enqueues 2 and 5; processing 2 first discovers/enqueues 7 and immediately marks it, so the edge from 5 does not enqueue it again. Both visit component {0,2,3,5,7,8}. The component pass uses fresh visited state, scans every vertex 0 through 8, starts a traversal at each unseen vertex and sorts each resulting membership list (or collects newly visited indices). Thus {1,4,6} is still recorded as the second component. Recursion versus queue scheduling changes order without changing reachability.



## Scope and dependency evidence checked after independent review

The DFS helper and graph-building loops must finish before traversal calls. BFS visit-at-enqueue happens within the neighbor guard, and the neighbor/queue loops finish before visited is cleared for the independent component pass. Empty order/component collections establish fresh result accumulation. These boundaries and initial states support DFS0,2,7,5,3,8, BFS0,2,5,7,3,8, first discovery of7 from2, and the separate component{1,4,6}.

Source: `main.rs`. Selected original locations: L1,L2,L3,L4,L5,L6,L7,L8,L9,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L35,L36,L37,L39,L41,L42,L43,L44,L45,L46,L47,L49,L50,L51,L52,L53,L54,L55,L56.

- L1: `fn dfs(v: usize, graph: &[[bool; 9]; 9], seen: &mut [bool; 9], order: &mut Vec<usize>) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `    seen[v] = true;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `    order.push(v);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `    for w in 0..9 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `        if graph[v][w] && !seen[w] {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `            dfs(w, graph, seen, order);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L8: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L9: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L12: `    let mut graph = [[false; 9]; 9];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    for [a, b] in [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `        [5, 0],` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `        [3, 8],` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `        [7, 2],` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `        [1, 6],` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `        [0, 2],` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `        [5, 3],` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `        [7, 5],` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `        [6, 4],` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `        [8, 7],` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `    ] {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `        graph[a][b] = true;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `        graph[b][a] = true;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L27: `    let mut seen = [false; 9];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `    let mut order = Vec::new();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `    dfs(0, &graph, &mut seen, &mut order);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `    seen.fill(false);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `    let mut queue = std::collections::VecDeque::from([0]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `    seen[0] = true;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `    while let Some(v) = queue.pop_front() {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `        for w in 0..9 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `            if graph[v][w] && !seen[w] {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L43: `                seen[w] = true;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `                queue.push_back(w);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `            }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L46: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L47: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L49: `    seen.fill(false);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L50: `    let mut components = Vec::new();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L51: `    for v in 0..9 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L52: `        if !seen[v] {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L53: `            let mut component = Vec::new();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L54: `            dfs(v, &graph, &mut seen, &mut component);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L55: `            component.sort();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L56: `            components.push(component);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **611 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 571 tokens. The contiguous original span L1–L56 costs 702 tokens; the complete original source costs 821 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 558 tokens; removes `fn dfs(v: usize, graph: &[[bool; 9]; 9], seen: &mut [bool; 9], order: &mut Vec<usize>) {` from the dependency chain described above.
- Without L2: 600 tokens; removes `seen[v] = true;` from the dependency chain described above.
- Without L3: 602 tokens; removes `order.push(v);` from the dependency chain described above.
- Without L4: 598 tokens; removes `for w in 0..9 {` from the dependency chain described above.
- Without L5: 589 tokens; removes `if graph[v][w] && !seen[w] {` from the dependency chain described above.
- Without L6: 593 tokens; removes `dfs(w, graph, seen, order);` from the dependency chain described above.
- Without L7: 607 tokens; removes `}` from the dependency chain described above.
- Without L8: 608 tokens; removes `}` from the dependency chain described above.
- Without L9: 609 tokens; removes `}` from the dependency chain described above.
- Without L12: 590 tokens; removes `let mut graph = [[false; 9]; 9];` from the dependency chain described above.
- Without L13: 597 tokens; removes `for [a, b] in [` from the dependency chain described above.
- Without L14: 601 tokens; removes `[5, 0],` from the dependency chain described above.
- Without L15: 601 tokens; removes `[3, 8],` from the dependency chain described above.
- Without L16: 601 tokens; removes `[7, 2],` from the dependency chain described above.
- Without L17: 601 tokens; removes `[1, 6],` from the dependency chain described above.
- Without L18: 601 tokens; removes `[0, 2],` from the dependency chain described above.
- Without L19: 601 tokens; removes `[5, 3],` from the dependency chain described above.
- Without L20: 601 tokens; removes `[7, 5],` from the dependency chain described above.
- Without L21: 601 tokens; removes `[6, 4],` from the dependency chain described above.
- Without L22: 601 tokens; removes `[8, 7],` from the dependency chain described above.
- Without L23: 606 tokens; removes `] {` from the dependency chain described above.
- Without L24: 596 tokens; removes `graph[a][b] = true;` from the dependency chain described above.
- Without L25: 596 tokens; removes `graph[b][a] = true;` from the dependency chain described above.
- Without L26: 608 tokens; removes `}` from the dependency chain described above.
- Without L27: 594 tokens; removes `let mut seen = [false; 9];` from the dependency chain described above.
- Without L28: 595 tokens; removes `let mut order = Vec::new();` from the dependency chain described above.
- Without L29: 588 tokens; removes `dfs(0, &graph, &mut seen, &mut order);` from the dependency chain described above.
- Without L35: 602 tokens; removes `seen.fill(false);` from the dependency chain described above.
- Without L36: 587 tokens; removes `let mut queue = std::collections::VecDeque::from([0]);` from the dependency chain described above.
- Without L37: 600 tokens; removes `seen[0] = true;` from the dependency chain described above.
- Without L39: 589 tokens; removes `while let Some(v) = queue.pop_front() {` from the dependency chain described above.
- Without L41: 597 tokens; removes `for w in 0..9 {` from the dependency chain described above.
- Without L42: 588 tokens; removes `if graph[v][w] && !seen[w] {` from the dependency chain described above.
- Without L43: 597 tokens; removes `seen[w] = true;` from the dependency chain described above.
- Without L44: 597 tokens; removes `queue.push_back(w);` from the dependency chain described above.
- Without L45: 606 tokens; removes `}` from the dependency chain described above.
- Without L46: 607 tokens; removes `}` from the dependency chain described above.
- Without L47: 608 tokens; removes `}` from the dependency chain described above.
- Without L49: 602 tokens; removes `seen.fill(false);` from the dependency chain described above.
- Without L50: 595 tokens; removes `let mut components = Vec::new();` from the dependency chain described above.
- Without L51: 598 tokens; removes `for v in 0..9 {` from the dependency chain described above.
- Without L52: 599 tokens; removes `if !seen[v] {` from the dependency chain described above.
- Without L53: 593 tokens; removes `let mut component = Vec::new();` from the dependency chain described above.
- Without L54: 586 tokens; removes `dfs(v, &graph, &mut seen, &mut component);` from the dependency chain described above.
- Without L55: 601 tokens; removes `component.sort();` from the dependency chain described above.
- Without L56: 600 tokens; removes `components.push(component);` from the dependency chain described above.
