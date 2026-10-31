# Task B selection: 80_graph_traversal / Julia

## Common answer requirements

Explain DFS versus FIFO BFS over component 0; trace first reach of vertex 7 and visit-mark timing; explain component coverage for omitted vertices independently of visit order.

## Answer and source dependencies

Ascending neighbors give DFS 0,2,7,5,3,8: recursive DFS marks 7 on entry after edge 2→7, before exploring its neighbors. FIFO BFS gives 0,2,5,7,3,8: processing 0 enqueues 2 and 5; processing 2 first discovers/enqueues 7 and immediately marks it, so the edge from 5 does not enqueue it again. Both visit component {0,2,3,5,7,8}. The component pass uses fresh visited state, scans every vertex 0 through 8, starts a traversal at each unseen vertex and sorts each resulting membership list (or collects newly visited indices). Thus {1,4,6} is still recorded as the second component. Recursion versus queue scheduling changes order without changing reachability.



## Scope and dependency evidence checked after independent review

The DFS helper and graph-building loops must finish before traversal calls. BFS visit-at-enqueue happens within the neighbor guard, and the neighbor/queue loops finish before visited is cleared for the independent component pass. Empty order/component collections establish fresh result accumulation. These boundaries and initial states support DFS0,2,7,5,3,8, BFS0,2,5,7,3,8, first discovery of7 from2, and the separate component{1,4,6}.

Source: `main.jl`. Selected original locations: L1,L2,L3,L4,L5,L6,L7,L10,L11,L12,L13,L14,L15,L16,L17,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L33,L34,L35,L36,L37,L38,L39.

- L1: `function dfs!(vertex, adjacency, visited, order)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `    visited[vertex+1] = true` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `    push!(order, vertex)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `    for neighbor in adjacency[vertex+1]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `        !visited[neighbor+1] && dfs!(neighbor, adjacency, visited, order)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `    end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L7: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L10: `    adjacency = [Int[] for vertex = 0:8]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    for (a, b) in [(5, 0), (3, 8), (7, 2), (1, 6), (0, 2), (5, 3), (7, 5), (6, 4), (8, 7)]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `        push!(adjacency[a+1], b)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `        push!(adjacency[b+1], a)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L15: `    foreach(sort!, adjacency)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `    order = Int[]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    dfs!(0, adjacency, falses(9), order)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `    queue, visited = [0], falses(9)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `    visited[1] = true` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `    head = 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `    while head <= length(queue)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `        vertex = queue[head]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `        head += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `        for neighbor in adjacency[vertex+1]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `            if !visited[neighbor+1]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `                visited[neighbor+1] = true` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `                push!(queue, neighbor)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `            end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L30: `        end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L31: `    end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L33: `    components = Vector{Int}[]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `    visited .= false` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `    for vertex = 0:8` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `        if !visited[vertex+1]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `            component = Int[]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `            dfs!(vertex, adjacency, visited, component)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `            push!(components, sort(component))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **480 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 441 tokens. The contiguous original span L1–L39 costs 529 tokens; the complete original source costs 609 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 463 tokens; removes `function dfs!(vertex, adjacency, visited, order)` from the dependency chain described above.
- Without L2: 468 tokens; removes `visited[vertex+1] = true` from the dependency chain described above.
- Without L3: 470 tokens; removes `push!(order, vertex)` from the dependency chain described above.
- Without L4: 466 tokens; removes `for neighbor in adjacency[vertex+1]` from the dependency chain described above.
- Without L5: 453 tokens; removes `!visited[neighbor+1] && dfs!(neighbor, adjacency, visited, order)` from the dependency chain described above.
- Without L6: 477 tokens; removes `end` from the dependency chain described above.
- Without L7: 478 tokens; removes `end` from the dependency chain described above.
- Without L10: 460 tokens; removes `adjacency = [Int[] for vertex = 0:8]` from the dependency chain described above.
- Without L11: 395 tokens; removes `for (a, b) in [(5, 0), (3, 8), (7, 2), (1, 6), (0, 2), (5, 3), (7, 5), (6, 4), (8, 7)]` from the dependency chain described above.
- Without L12: 464 tokens; removes `push!(adjacency[a+1], b)` from the dependency chain described above.
- Without L13: 464 tokens; removes `push!(adjacency[b+1], a)` from the dependency chain described above.
- Without L14: 477 tokens; removes `end` from the dependency chain described above.
- Without L15: 470 tokens; removes `foreach(sort!, adjacency)` from the dependency chain described above.
- Without L16: 472 tokens; removes `order = Int[]` from the dependency chain described above.
- Without L17: 461 tokens; removes `dfs!(0, adjacency, falses(9), order)` from the dependency chain described above.
- Without L19: 462 tokens; removes `queue, visited = [0], falses(9)` from the dependency chain described above.
- Without L20: 470 tokens; removes `visited[1] = true` from the dependency chain described above.
- Without L21: 473 tokens; removes `head = 1` from the dependency chain described above.
- Without L22: 468 tokens; removes `while head <= length(queue)` from the dependency chain described above.
- Without L23: 469 tokens; removes `vertex = queue[head]` from the dependency chain described above.
- Without L24: 472 tokens; removes `head += 1` from the dependency chain described above.
- Without L25: 465 tokens; removes `for neighbor in adjacency[vertex+1]` from the dependency chain described above.
- Without L26: 467 tokens; removes `if !visited[neighbor+1]` from the dependency chain described above.
- Without L27: 465 tokens; removes `visited[neighbor+1] = true` from the dependency chain described above.
- Without L28: 467 tokens; removes `push!(queue, neighbor)` from the dependency chain described above.
- Without L29: 475 tokens; removes `end` from the dependency chain described above.
- Without L30: 476 tokens; removes `end` from the dependency chain described above.
- Without L31: 477 tokens; removes `end` from the dependency chain described above.
- Without L33: 469 tokens; removes `components = Vector{Int}[]` from the dependency chain described above.
- Without L34: 473 tokens; removes `visited .= false` from the dependency chain described above.
- Without L35: 469 tokens; removes `for vertex = 0:8` from the dependency chain described above.
- Without L36: 468 tokens; removes `if !visited[vertex+1]` from the dependency chain described above.
- Without L37: 470 tokens; removes `component = Int[]` from the dependency chain described above.
- Without L38: 462 tokens; removes `dfs!(vertex, adjacency, visited, component)` from the dependency chain described above.
- Without L39: 465 tokens; removes `push!(components, sort(component))` from the dependency chain described above.
