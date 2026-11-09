# Task B: 80_graph_traversal / Julia

The unordered edges build both directions of an undirected graph and neighbors are visited in ascending numeric order. DFS from 0 is `0 2 7 5 3 8`: 7 is first reached recursively from 2. BFS from 0 is `0 2 5 7 3 8`: 7 is first marked/enqueued while expanding 2, and each vertex is marked on discovery so it is queued once. Restart component search at the smallest unseen vertex, sort each discovered component for display, and number components from 1. Components are `0 2 3 5 7 8` and `1 4 6`.

Sorted adjacency vectors supply stable neighbor order; the DFS routine and BFS seen-on-enqueue block share graph values, then component discovery resets seen.

Evidence is from `main.jl`, L1,L2,L3,L4,L5,L6,L7,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41,L42,L43,L44,L45.

- L1: `function dfs!(vertex, adjacency, visited, order)`
- L2: `visited[vertex+1] = true`
- L3: `push!(order, vertex)`
- L4: `for neighbor in adjacency[vertex+1]`
- L5: `!visited[neighbor+1] && dfs!(neighbor, adjacency, visited, order)`
- L6: `end`
- L7: `end`
- L10: `adjacency = [Int[] for vertex = 0:8]`
- L11: `for (a, b) in [(5, 0), (3, 8), (7, 2), (1, 6), (0, 2), (5, 3), (7, 5), (6, 4), (8, 7)]`
- L12: `push!(adjacency[a+1], b)`
- L13: `push!(adjacency[b+1], a)`
- L14: `end`
- L15: `foreach(sort!, adjacency)`
- L16: `order = Int[]`
- L17: `dfs!(0, adjacency, falses(9), order)`
- L18: `println("DFS: ", join(order, " "))`
- L19: `queue, visited = [0], falses(9)`
- L20: `visited[1] = true`
- L21: `head = 1`
- L22: `while head <= length(queue)`
- L23: `vertex = queue[head]`
- L24: `head += 1`
- L25: `for neighbor in adjacency[vertex+1]`
- L26: `if !visited[neighbor+1]`
- L27: `visited[neighbor+1] = true`
- L28: `push!(queue, neighbor)`
- L29: `end`
- L30: `end`
- L31: `end`
- L32: `println("BFS: ", join(queue, " "))`
- L33: `components = Vector{Int}[]`
- L34: `visited .= false`
- L35: `for vertex = 0:8`
- L36: `if !visited[vertex+1]`
- L37: `component = Int[]`
- L38: `dfs!(vertex, adjacency, visited, component)`
- L39: `push!(components, sort(component))`
- L40: `end`
- L41: `end`
- L42: `println("components: ", length(components))`
- L43: `for (number, component) in enumerate(components)`
- L44: `println("component ", number, ": ", join(component, " "))`
- L45: `end`

Minimization: The graph data/construction, sorted neighbor rule, complete DFS/BFS and restarted component traversal/formatting are necessary for this end-to-end result. Imports and outer wrappers are omitted. The selected complete original lines, in source order, cost 595 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 601, and the complete source costs 607. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
