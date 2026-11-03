# Task B selection: 80_graph_traversal / C#

## Common answer requirements

Explain DFS versus FIFO BFS over component 0; trace first reach of vertex 7 and visit-mark timing; explain component coverage for omitted vertices independently of visit order.

## Answer and source dependencies

Ascending neighbors give DFS 0,2,7,5,3,8: recursive DFS marks 7 on entry after edge 2→7, before exploring its neighbors. FIFO BFS gives 0,2,5,7,3,8: processing 0 enqueues 2 and 5; processing 2 first discovers/enqueues 7 and immediately marks it, so the edge from 5 does not enqueue it again. Both visit component {0,2,3,5,7,8}. The component pass uses fresh visited state, scans every vertex 0 through 8, starts a traversal at each unseen vertex and sorts each resulting membership list (or collects newly visited indices). Thus {1,4,6} is still recorded as the second component. Recursion versus queue scheduling changes order without changing reachability.



## Scope and dependency evidence checked after independent review

The DFS helper and graph-building loops must finish before traversal calls. BFS visit-at-enqueue happens within the neighbor guard, and the neighbor/queue loops finish before visited is cleared for the independent component pass. Empty order/component collections establish fresh result accumulation. These boundaries and initial states support DFS0,2,7,5,3,8, BFS0,2,5,7,3,8, first discovery of7 from2, and the separate component{1,4,6}.

Source: `Program.cs`. Selected original locations: L7,L8,L9,L10,L11,L12,L13,L14,L15,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41,L42,L43,L44,L45,L46,L47,L48,L49,L50,L51,L52,L53.

- L7: `static void Dfs(int v, bool[,] graph, bool[] seen, List<int> order)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `{` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L9: `    seen[v] = true;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    order.Add(v);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    for (int w = 0; w < seen.Length; w++)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    {` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L13: `        if (graph[v, w] && !seen[w]) Dfs(w, graph, seen, order);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L15: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L17: `bool[,] graph = new bool[9, 9];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `var edges = new[] { (5, 0), (3, 8), (7, 2), (1, 6), (0, 2), (5, 3), (7, 5), (6, 4), (8, 7) };` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `foreach (var (a, b) in edges)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `{` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L21: `    graph[a, b] = true;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `    graph[b, a] = true;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L24: `var depth = new List<int>();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `Dfs(0, graph, new bool[9], depth);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `bool[] seen = new bool[9];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `var queue = new Queue<int>();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `var breadth = new List<int>();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `seen[0] = true;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `queue.Enqueue(0);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `while (queue.Count > 0)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `{` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L33: `    int v = queue.Dequeue();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `    breadth.Add(v);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `    for (int w = 0; w < 9; w++)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `    {` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L37: `        if (graph[v, w] && !seen[w])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `        {` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L39: `            seen[w] = true;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `            queue.Enqueue(w);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L42: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L43: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L44: `var components = new List<List<int>>();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `Array.Fill(seen, false);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `for (int v = 0; v < 9; v++)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L47: `{` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L48: `    if (!seen[v])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `    {` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L50: `        var component = new List<int>();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L51: `        Dfs(v, graph, seen, component);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L52: `        component.Sort();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L53: `        components.Add(component);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **626 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 548 tokens. The contiguous original span L7–L53 costs 627 tokens; the complete original source costs 805 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L7: 593 tokens; removes `static void Dfs(int v, bool[,] graph, bool[] seen, List<int> order)` from the dependency chain described above.
- Without L8: 624 tokens; removes `{` from the dependency chain described above.
- Without L9: 615 tokens; removes `seen[v] = true;` from the dependency chain described above.
- Without L10: 617 tokens; removes `order.Add(v);` from the dependency chain described above.
- Without L11: 600 tokens; removes `for (int w = 0; w < seen.Length; w++)` from the dependency chain described above.
- Without L12: 623 tokens; removes `{` from the dependency chain described above.
- Without L13: 589 tokens; removes `if (graph[v, w] && !seen[w]) Dfs(w, graph, seen, order);` from the dependency chain described above.
- Without L14: 623 tokens; removes `}` from the dependency chain described above.
- Without L15: 624 tokens; removes `}` from the dependency chain described above.
- Without L17: 606 tokens; removes `bool[,] graph = new bool[9, 9];` from the dependency chain described above.
- Without L18: 541 tokens; removes `var edges = new[] { (5, 0), (3, 8), (7, 2), (1, 6), (0, 2), (5, 3), (7, 5), (6, 4), (8, 7) };` from the dependency chain described above.
- Without L19: 609 tokens; removes `foreach (var (a, b) in edges)` from the dependency chain described above.
- Without L20: 624 tokens; removes `{` from the dependency chain described above.
- Without L21: 612 tokens; removes `graph[a, b] = true;` from the dependency chain described above.
- Without L22: 612 tokens; removes `graph[b, a] = true;` from the dependency chain described above.
- Without L23: 624 tokens; removes `}` from the dependency chain described above.
- Without L24: 610 tokens; removes `var depth = new List<int>();` from the dependency chain described above.
- Without L25: 606 tokens; removes `Dfs(0, graph, new bool[9], depth);` from the dependency chain described above.
- Without L26: 611 tokens; removes `bool[] seen = new bool[9];` from the dependency chain described above.
- Without L27: 610 tokens; removes `var queue = new Queue<int>();` from the dependency chain described above.
- Without L28: 610 tokens; removes `var breadth = new List<int>();` from the dependency chain described above.
- Without L29: 616 tokens; removes `seen[0] = true;` from the dependency chain described above.
- Without L30: 618 tokens; removes `queue.Enqueue(0);` from the dependency chain described above.
- Without L31: 614 tokens; removes `while (queue.Count > 0)` from the dependency chain described above.
- Without L32: 624 tokens; removes `{` from the dependency chain described above.
- Without L33: 612 tokens; removes `int v = queue.Dequeue();` from the dependency chain described above.
- Without L34: 617 tokens; removes `breadth.Add(v);` from the dependency chain described above.
- Without L35: 602 tokens; removes `for (int w = 0; w < 9; w++)` from the dependency chain described above.
- Without L36: 623 tokens; removes `{` from the dependency chain described above.
- Without L37: 604 tokens; removes `if (graph[v, w] && !seen[w])` from the dependency chain described above.
- Without L38: 622 tokens; removes `{` from the dependency chain described above.
- Without L39: 613 tokens; removes `seen[w] = true;` from the dependency chain described above.
- Without L40: 615 tokens; removes `queue.Enqueue(w);` from the dependency chain described above.
- Without L41: 622 tokens; removes `}` from the dependency chain described above.
- Without L42: 623 tokens; removes `}` from the dependency chain described above.
- Without L43: 624 tokens; removes `}` from the dependency chain described above.
- Without L44: 608 tokens; removes `var components = new List<List<int>>();` from the dependency chain described above.
- Without L45: 615 tokens; removes `Array.Fill(seen, false);` from the dependency chain described above.
- Without L46: 603 tokens; removes `for (int v = 0; v < 9; v++)` from the dependency chain described above.
- Without L47: 624 tokens; removes `{` from the dependency chain described above.
- Without L48: 615 tokens; removes `if (!seen[v])` from the dependency chain described above.
- Without L49: 623 tokens; removes `{` from the dependency chain described above.
- Without L50: 608 tokens; removes `var component = new List<int>();` from the dependency chain described above.
- Without L51: 609 tokens; removes `Dfs(v, graph, seen, component);` from the dependency chain described above.
- Without L52: 617 tokens; removes `component.Sort();` from the dependency chain described above.
- Without L53: 616 tokens; removes `components.Add(component);` from the dependency chain described above.
