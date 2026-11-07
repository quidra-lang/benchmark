# Task B: 89_dijkstra / J

Initialize unreached vertices with finite 1000 while preserving distance[source]=0 immediately afterward. The graph has seven vertices and positive weights at most 9, so any finite shortest route can be simple with at most six edges, bounded by 54<1000. Thus this default does not collide with any finite shortest distance here; relaxation/path logic needs no change.

Replace the unreached literal in the distance vector initializer, retaining its source-zero amendment.

Evidence is from `main.ijs`, L2,L3,L10.

- L2: `names =. 'ABCDEFG'`
- L3: `edges =. 11 3$0 1 7 0 2 3 0 3 9 1 2 2 2 4 6 1 3 3 3 4 4 3 5 5 4 5 3 4 6 8 5 6 4`
- L10: `distance =. 0,6$_`

Minimization: The vertex/weight data and distance initializer/source override justify this expression-only default change. The relaxation loop and path report are intentionally omitted. The selected complete original lines, in source order, cost 96 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 165, and the complete source costs 485. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
