# Task B selection: 80_graph_traversal / Lua

## Common answer requirements

Explain DFS versus FIFO BFS over component 0; trace first reach of vertex 7 and visit-mark timing; explain component coverage for omitted vertices independently of visit order.

## Answer and source dependencies

Ascending neighbors give DFS 0,2,7,5,3,8: recursive DFS marks 7 on entry after edge 2→7, before exploring its neighbors. FIFO BFS gives 0,2,5,7,3,8: processing 0 enqueues 2 and 5; processing 2 first discovers/enqueues 7 and immediately marks it, so the edge from 5 does not enqueue it again. Both visit component {0,2,3,5,7,8}. The component pass uses fresh visited state, scans every vertex 0 through 8, starts a traversal at each unseen vertex and sorts each resulting membership list (or collects newly visited indices). Thus {1,4,6} is still recorded as the second component. Recursion versus queue scheduling changes order without changing reachability.



## Scope and dependency evidence checked after independent review

The DFS helper and graph-building loops must finish before traversal calls. BFS visit-at-enqueue happens within the neighbor guard, and the neighbor/queue loops finish before visited is cleared for the independent component pass. Empty order/component collections establish fresh result accumulation. These boundaries and initial states support DFS0,2,7,5,3,8, BFS0,2,5,7,3,8, first discovery of7 from2, and the separate component{1,4,6}.

Source: `main.lua`. Selected original locations: L1,L2,L3,L4,L5,L6,L7,L8,L10,L11,L12,L13,L14,L15,L16,L18,L19,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L33,L34,L35,L36,L37,L38,L39,L40.

- L1: `local adjacency = {}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `for vertex = 0, 8 do adjacency[vertex] = {} end` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `for _, edge in ipairs({{5, 0}, {3, 8}, {7, 2}, {1, 6}, {0, 2}, {5, 3}, {7, 5}, {6, 4}, {8, 7}}) do` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `    local a, b = table.unpack(edge)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `    adjacency[a][#adjacency[a] + 1] = b` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `    adjacency[b][#adjacency[b] + 1] = a` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L8: `for vertex = 0, 8 do table.sort(adjacency[vertex]) end` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `local function dfs(vertex, seen, order)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    seen[vertex] = true` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    order[#order + 1] = vertex` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    for _, neighbor in ipairs(adjacency[vertex]) do` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `        if not seen[neighbor] then dfs(neighbor, seen, order) end` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L16: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L18: `local order = {}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `dfs(0, {}, order)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `local queue, seen, head = {0}, {[0] = true}, 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `while head <= #queue do` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `    local vertex = queue[head]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `    head = head + 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `    for _, neighbor in ipairs(adjacency[vertex]) do` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `        if not seen[neighbor] then` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `            seen[neighbor] = true` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `            queue[#queue + 1] = neighbor` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `        end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L30: `    end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L31: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L33: `local components = {}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `seen = {}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `for vertex = 0, 8 do` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `    if not seen[vertex] then` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `        local component = {}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `        dfs(vertex, seen, component)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `        table.sort(component)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `        components[#components + 1] = component` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **544 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 501 tokens. The contiguous original span L1–L40 costs 606 tokens; the complete original source costs 692 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 535 tokens; removes `local adjacency = {}` from the dependency chain described above.
- Without L2: 519 tokens; removes `for vertex = 0, 8 do adjacency[vertex] = {} end` from the dependency chain described above.
- Without L3: 457 tokens; removes `for _, edge in ipairs({{5, 0}, {3, 8}, {7, 2}, {1, 6}, {0, 2}, {5, 3}, {7, 5}, {6, 4}, {8, 7}}) do` from the dependency chain described above.
- Without L4: 527 tokens; removes `local a, b = table.unpack(edge)` from the dependency chain described above.
- Without L5: 523 tokens; removes `adjacency[a][#adjacency[a] + 1] = b` from the dependency chain described above.
- Without L6: 523 tokens; removes `adjacency[b][#adjacency[b] + 1] = a` from the dependency chain described above.
- Without L7: 542 tokens; removes `end` from the dependency chain described above.
- Without L8: 519 tokens; removes `for vertex = 0, 8 do table.sort(adjacency[vertex]) end` from the dependency chain described above.
- Without L10: 529 tokens; removes `local function dfs(vertex, seen, order)` from the dependency chain described above.
- Without L11: 534 tokens; removes `seen[vertex] = true` from the dependency chain described above.
- Without L12: 529 tokens; removes `order[#order + 1] = vertex` from the dependency chain described above.
- Without L13: 524 tokens; removes `for _, neighbor in ipairs(adjacency[vertex]) do` from the dependency chain described above.
- Without L14: 518 tokens; removes `if not seen[neighbor] then dfs(neighbor, seen, order) end` from the dependency chain described above.
- Without L15: 541 tokens; removes `end` from the dependency chain described above.
- Without L16: 542 tokens; removes `end` from the dependency chain described above.
- Without L18: 535 tokens; removes `local order = {}` from the dependency chain described above.
- Without L19: 532 tokens; removes `dfs(0, {}, order)` from the dependency chain described above.
- Without L21: 514 tokens; removes `local queue, seen, head = {0}, {[0] = true}, 1` from the dependency chain described above.
- Without L22: 533 tokens; removes `while head <= #queue do` from the dependency chain described above.
- Without L23: 532 tokens; removes `local vertex = queue[head]` from the dependency chain described above.
- Without L24: 533 tokens; removes `head = head + 1` from the dependency chain described above.
- Without L25: 524 tokens; removes `for _, neighbor in ipairs(adjacency[vertex]) do` from the dependency chain described above.
- Without L26: 531 tokens; removes `if not seen[neighbor] then` from the dependency chain described above.
- Without L27: 532 tokens; removes `seen[neighbor] = true` from the dependency chain described above.
- Without L28: 527 tokens; removes `queue[#queue + 1] = neighbor` from the dependency chain described above.
- Without L29: 540 tokens; removes `end` from the dependency chain described above.
- Without L30: 541 tokens; removes `end` from the dependency chain described above.
- Without L31: 542 tokens; removes `end` from the dependency chain described above.
- Without L33: 535 tokens; removes `local components = {}` from the dependency chain described above.
- Without L34: 537 tokens; removes `seen = {}` from the dependency chain described above.
- Without L35: 531 tokens; removes `for vertex = 0, 8 do` from the dependency chain described above.
- Without L36: 532 tokens; removes `if not seen[vertex] then` from the dependency chain described above.
- Without L37: 533 tokens; removes `local component = {}` from the dependency chain described above.
- Without L38: 531 tokens; removes `dfs(vertex, seen, component)` from the dependency chain described above.
- Without L39: 535 tokens; removes `table.sort(component)` from the dependency chain described above.
- Without L40: 528 tokens; removes `components[#components + 1] = component` from the dependency chain described above.
