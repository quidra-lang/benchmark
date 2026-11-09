# Task B: 89_dijkstra / Julia

Initialize unreached vertices with finite 1000 while preserving distance[source]=0 immediately afterward. The graph has seven vertices and positive weights at most 9, so any finite shortest route can be simple with at most six edges, bounded by 54<1000. Thus this default does not collide with any finite shortest distance here; relaxation/path logic needs no change.

Replace the sentinel in fill(...,length(names)); the separate source assignment remains zero.

Evidence is from `main.jl`, L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L21,L24.

- L3: `weights = zeros(Int, 7, 7)`
- L4: `edges = [`
- L5: `('A', 'B', 7),`
- L6: `('A', 'C', 3),`
- L7: `('A', 'D', 9),`
- L8: `('B', 'C', 2),`
- L9: `('C', 'E', 6),`
- L10: `('B', 'D', 3),`
- L11: `('D', 'E', 4),`
- L12: `('D', 'F', 5),`
- L13: `('E', 'F', 3),`
- L14: `('E', 'G', 8),`
- L15: `('F', 'G', 4),`
- L16: `]`
- L21: `distance = fill(typemax(Int), 7)`
- L24: `distance[1] = 0`

Minimization: The vertex/weight data and distance initializer/source override justify this expression-only default change. The relaxation loop and path report are intentionally omitted. The selected complete original lines, in source order, cost 239 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 344, and the complete source costs 635. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
