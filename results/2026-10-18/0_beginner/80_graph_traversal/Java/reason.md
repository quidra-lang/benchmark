# Task B selection: 80_graph_traversal / Java

## Common answer requirements

Explain DFS versus FIFO BFS over component 0; trace first reach of vertex 7 and visit-mark timing; explain component coverage for omitted vertices independently of visit order.

## Answer and source dependencies

Ascending neighbors give DFS 0,2,7,5,3,8: recursive DFS marks 7 on entry after edge 2→7, before exploring its neighbors. FIFO BFS gives 0,2,5,7,3,8: processing 0 enqueues 2 and 5; processing 2 first discovers/enqueues 7 and immediately marks it, so the edge from 5 does not enqueue it again. Both visit component {0,2,3,5,7,8}. The component pass uses fresh visited state, scans every vertex 0 through 8, starts a traversal at each unseen vertex and sorts each resulting membership list (or collects newly visited indices). Thus {1,4,6} is still recorded as the second component. Recursion versus queue scheduling changes order without changing reachability.



## Scope and dependency evidence checked after independent review

The DFS helper and graph-building loops must finish before traversal calls. BFS visit-at-enqueue happens within the neighbor guard, and the neighbor/queue loops finish before visited is cleared for the independent component pass. Empty order/component collections establish fresh result accumulation. These boundaries and initial states support DFS0,2,7,5,3,8, BFS0,2,5,7,3,8, first discovery of7 from2, and the separate component{1,4,6}.

Source: `Main.java`. Selected original locations: L9,L10,L11,L12,L13,L14,L15,L16,L17,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41,L42,L43,L44,L45,L46,L47,L48,L49,L50,L51,L52,L53,L54.

- L9: `    static void dfs(int v, boolean[][] graph, boolean[] seen, List<Integer> order) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `        seen[v] = true;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `        order.add(v);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `        for (int w = 0; w < graph.length; w++) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `            if (graph[v][w] && !seen[w]) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `                dfs(w, graph, seen, order);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `            }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L16: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L17: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L24: `        boolean[][] graph = new boolean[9][9];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `        int[][] edges = {{5, 0}, {3, 8}, {7, 2}, {1, 6}, {0, 2}, {5, 3}, {7, 5}, {6, 4}, {8, 7}};` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `        for (int[] edge : edges) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `            graph[edge[0]][edge[1]] = true;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `            graph[edge[1]][edge[0]] = true;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L30: `        List<Integer> depth = new ArrayList<>();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `        dfs(0, graph, new boolean[9], depth);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `        boolean[] seen = new boolean[9];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `        Deque<Integer> queue = new ArrayDeque<>();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `        List<Integer> breadth = new ArrayList<>();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `        seen[0] = true;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `        queue.add(0);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `        while (!queue.isEmpty()) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `            int v = queue.remove();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `            breadth.add(v);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `            for (int w = 0; w < 9; w++) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `                if (graph[v][w] && !seen[w]) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `                    seen[w] = true;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L43: `                    queue.add(w);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `                }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L45: `            }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L46: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L47: `        List<List<Integer>> components = new ArrayList<>();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `        Arrays.fill(seen, false);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `        for (int v = 0; v < 9; v++) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L50: `            if (!seen[v]) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L51: `                List<Integer> component = new ArrayList<>();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L52: `                dfs(v, graph, seen, component);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L53: `                Collections.sort(component);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L54: `                components.add(component);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **716 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 630 tokens. The contiguous original span L9–L54 costs 789 tokens; the complete original source costs 1018 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L9: 681 tokens; removes `static void dfs(int v, boolean[][] graph, boolean[] seen, List<Integer> order) {` from the dependency chain described above.
- Without L10: 704 tokens; removes `seen[v] = true;` from the dependency chain described above.
- Without L11: 706 tokens; removes `order.add(v);` from the dependency chain described above.
- Without L12: 687 tokens; removes `for (int w = 0; w < graph.length; w++) {` from the dependency chain described above.
- Without L13: 691 tokens; removes `if (graph[v][w] && !seen[w]) {` from the dependency chain described above.
- Without L14: 697 tokens; removes `dfs(w, graph, seen, order);` from the dependency chain described above.
- Without L15: 711 tokens; removes `}` from the dependency chain described above.
- Without L16: 712 tokens; removes `}` from the dependency chain described above.
- Without L17: 713 tokens; removes `}` from the dependency chain described above.
- Without L24: 695 tokens; removes `boolean[][] graph = new boolean[9][9];` from the dependency chain described above.
- Without L25: 632 tokens; removes `int[][] edges = {{5, 0}, {3, 8}, {7, 2}, {1, 6}, {0, 2}, {5, 3}, {7, 5}, {6, 4}, {8, 7}};` from the dependency chain described above.
- Without L26: 699 tokens; removes `for (int[] edge : edges) {` from the dependency chain described above.
- Without L27: 696 tokens; removes `graph[edge[0]][edge[1]] = true;` from the dependency chain described above.
- Without L28: 696 tokens; removes `graph[edge[1]][edge[0]] = true;` from the dependency chain described above.
- Without L29: 712 tokens; removes `}` from the dependency chain described above.
- Without L30: 695 tokens; removes `List<Integer> depth = new ArrayList<>();` from the dependency chain described above.
- Without L31: 694 tokens; removes `dfs(0, graph, new boolean[9], depth);` from the dependency chain described above.
- Without L32: 699 tokens; removes `boolean[] seen = new boolean[9];` from the dependency chain described above.
- Without L33: 695 tokens; removes `Deque<Integer> queue = new ArrayDeque<>();` from the dependency chain described above.
- Without L34: 695 tokens; removes `List<Integer> breadth = new ArrayList<>();` from the dependency chain described above.
- Without L35: 704 tokens; removes `seen[0] = true;` from the dependency chain described above.
- Without L36: 706 tokens; removes `queue.add(0);` from the dependency chain described above.
- Without L37: 700 tokens; removes `while (!queue.isEmpty()) {` from the dependency chain described above.
- Without L38: 700 tokens; removes `int v = queue.remove();` from the dependency chain described above.
- Without L39: 705 tokens; removes `breadth.add(v);` from the dependency chain described above.
- Without L40: 688 tokens; removes `for (int w = 0; w < 9; w++) {` from the dependency chain described above.
- Without L41: 690 tokens; removes `if (graph[v][w] && !seen[w]) {` from the dependency chain described above.
- Without L42: 701 tokens; removes `seen[w] = true;` from the dependency chain described above.
- Without L43: 703 tokens; removes `queue.add(w);` from the dependency chain described above.
- Without L44: 710 tokens; removes `}` from the dependency chain described above.
- Without L45: 711 tokens; removes `}` from the dependency chain described above.
- Without L46: 712 tokens; removes `}` from the dependency chain described above.
- Without L47: 693 tokens; removes `List<List<Integer>> components = new ArrayList<>();` from the dependency chain described above.
- Without L48: 703 tokens; removes `Arrays.fill(seen, false);` from the dependency chain described above.
- Without L49: 689 tokens; removes `for (int v = 0; v < 9; v++) {` from the dependency chain described above.
- Without L50: 701 tokens; removes `if (!seen[v]) {` from the dependency chain described above.
- Without L51: 693 tokens; removes `List<Integer> component = new ArrayList<>();` from the dependency chain described above.
- Without L52: 697 tokens; removes `dfs(v, graph, seen, component);` from the dependency chain described above.
- Without L53: 704 tokens; removes `Collections.sort(component);` from the dependency chain described above.
- Without L54: 704 tokens; removes `components.add(component);` from the dependency chain described above.
