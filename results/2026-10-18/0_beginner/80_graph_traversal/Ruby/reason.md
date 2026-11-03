# Task B selection: 80_graph_traversal / Ruby

## Common answer requirements

Explain DFS versus FIFO BFS over component 0; trace first reach of vertex 7 and visit-mark timing; explain component coverage for omitted vertices independently of visit order.

## Answer and source dependencies

Ascending neighbors give DFS 0,2,7,5,3,8: recursive DFS marks 7 on entry after edge 2→7, before exploring its neighbors. FIFO BFS gives 0,2,5,7,3,8: processing 0 enqueues 2 and 5; processing 2 first discovers/enqueues 7 and immediately marks it, so the edge from 5 does not enqueue it again. Both visit component {0,2,3,5,7,8}. The component pass uses fresh visited state, scans every vertex 0 through 8, starts a traversal at each unseen vertex and sorts each resulting membership list (or collects newly visited indices). Thus {1,4,6} is still recorded as the second component. Recursion versus queue scheduling changes order without changing reachability.



## Scope and dependency evidence checked after independent review

The DFS helper and graph-building loops must finish before traversal calls. BFS visit-at-enqueue happens within the neighbor guard, and the neighbor/queue loops finish before visited is cleared for the independent component pass. Empty order/component collections establish fresh result accumulation. These boundaries and initial states support DFS0,2,7,5,3,8, BFS0,2,5,7,3,8, first discovery of7 from2, and the separate component{1,4,6}.

Source: `main.rb`. Selected original locations: L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34.

- L1: `edges = [[5, 0], [3, 8], [7, 2], [1, 6], [0, 2], [5, 3], [7, 5], [6, 4], [8, 7]]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `graph = Array.new(9) { [] }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `edges.each do |a, b|` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `  graph[a] << b` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `  graph[b] << a` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L7: `graph.each(&:sort!)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `dfs = lambda do |vertex, seen, order|` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `  seen.add(vertex)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `  order << vertex` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `  graph[vertex].each { |neighbor| dfs.call(neighbor, seen, order) unless seen.include?(neighbor) }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L13: `depth = []` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `dfs.call(0, Set.new, depth)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `queue = [0]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `seen = Set[0]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `breadth = []` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `until queue.empty?` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `  vertex = queue.shift` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `  breadth << vertex` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `  graph[vertex].each do |neighbor|` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `    unless seen.include?(neighbor)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `      seen.add(neighbor)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `      queue << neighbor` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `    end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L26: `  end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L27: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L28: `components = []` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `seen = Set.new` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `9.times do |vertex|` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `  unless seen.include?(vertex)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `    component = []` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `    dfs.call(vertex, seen, component)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `    components << component.sort` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **390 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 366 tokens. The contiguous original span L1–L34 costs 390 tokens; the complete original source costs 493 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 315 tokens; removes `edges = [[5, 0], [3, 8], [7, 2], [1, 6], [0, 2], [5, 3], [7, 5], [6, 4], [8, 7]]` from the dependency chain described above.
- Without L2: 373 tokens; removes `graph = Array.new(9) { [] }` from the dependency chain described above.
- Without L3: 377 tokens; removes `edges.each do |a, b|` from the dependency chain described above.
- Without L4: 380 tokens; removes `graph[a] << b` from the dependency chain described above.
- Without L5: 380 tokens; removes `graph[b] << a` from the dependency chain described above.
- Without L6: 388 tokens; removes `end` from the dependency chain described above.
- Without L7: 381 tokens; removes `graph.each(&:sort!)` from the dependency chain described above.
- Without L8: 372 tokens; removes `dfs = lambda do |vertex, seen, order|` from the dependency chain described above.
- Without L9: 382 tokens; removes `seen.add(vertex)` from the dependency chain described above.
- Without L10: 383 tokens; removes `order << vertex` from the dependency chain described above.
- Without L11: 352 tokens; removes `graph[vertex].each { |neighbor| dfs.call(neighbor, seen, order) unless seen.include?(neighbor) }` from the dependency chain described above.
- Without L12: 388 tokens; removes `end` from the dependency chain described above.
- Without L13: 384 tokens; removes `depth = []` from the dependency chain described above.
- Without L14: 375 tokens; removes `dfs.call(0, Set.new, depth)` from the dependency chain described above.
- Without L15: 382 tokens; removes `queue = [0]` from the dependency chain described above.
- Without L16: 381 tokens; removes `seen = Set[0]` from the dependency chain described above.
- Without L17: 384 tokens; removes `breadth = []` from the dependency chain described above.
- Without L18: 383 tokens; removes `until queue.empty?` from the dependency chain described above.
- Without L19: 381 tokens; removes `vertex = queue.shift` from the dependency chain described above.
- Without L20: 383 tokens; removes `breadth << vertex` from the dependency chain described above.
- Without L21: 377 tokens; removes `graph[vertex].each do |neighbor|` from the dependency chain described above.
- Without L22: 379 tokens; removes `unless seen.include?(neighbor)` from the dependency chain described above.
- Without L23: 381 tokens; removes `seen.add(neighbor)` from the dependency chain described above.
- Without L24: 382 tokens; removes `queue << neighbor` from the dependency chain described above.
- Without L25: 387 tokens; removes `end` from the dependency chain described above.
- Without L26: 387 tokens; removes `end` from the dependency chain described above.
- Without L27: 388 tokens; removes `end` from the dependency chain described above.
- Without L28: 384 tokens; removes `components = []` from the dependency chain described above.
- Without L29: 382 tokens; removes `seen = Set.new` from the dependency chain described above.
- Without L30: 380 tokens; removes `9.times do |vertex|` from the dependency chain described above.
- Without L31: 379 tokens; removes `unless seen.include?(vertex)` from the dependency chain described above.
- Without L32: 383 tokens; removes `component = []` from the dependency chain described above.
- Without L33: 376 tokens; removes `dfs.call(vertex, seen, component)` from the dependency chain described above.
- Without L34: 381 tokens; removes `components << component.sort` from the dependency chain described above.
