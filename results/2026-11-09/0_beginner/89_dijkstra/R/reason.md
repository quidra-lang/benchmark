# Task B: 89_dijkstra / R

Initialize unreached vertices with finite 1000 while preserving distance[source]=0 immediately afterward. The graph has seven vertices and positive weights at most 9, so any finite shortest route can be simple with at most six edges, bounded by 54<1000. Thus this default does not collide with any finite shortest distance here; relaxation/path logic needs no change.

Replace rep(Inf,length(names)) with the finite default and retain distance[source]<-0.

Evidence is from `main.R`, L1,L3,L4,L5,L6,L12,L15.

- L1: `names <- LETTERS[1:7]`
- L3: `edges <- data.frame(`
- L4: `from = c("A", "A", "A", "B", "C", "B", "D", "D", "E", "E", "F"),`
- L5: `to = c("B", "C", "D", "C", "E", "D", "E", "F", "F", "G", "G"), weight = c(7, 3, 9, 2, 6, 3, 4, 5, 3, 8, 4)`
- L6: `)`
- L12: `distance <- rep(Inf, 7)`
- L15: `distance[1] <- 0`

Minimization: The vertex/weight data and distance initializer/source override justify this expression-only default change. The relaxation loop and path report are intentionally omitted. The selected complete original lines, in source order, cost 208 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 330, and the complete source costs 610. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
