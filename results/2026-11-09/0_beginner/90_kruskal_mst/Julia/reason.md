# Task B: 90_kruskal_mst / Julia

Sort all thirteen edges by ascending weight and normalize displayed endpoint names alphabetically. Accept GH:2,CE:3,AC:4,DE:5,AB:7,FG:8,EH:10, totaling 39. At weight 5, D and E are in different components and union succeeds; at weight 6, D and C already share a component, so DC is rejected. BC:9 is the other rejection. EH:10 is the seventh accepted edge, so the n-1 stop occurs immediately and later edges (starting DF:11) are not examined; skipped=2.

The root function supplies component identities; union writes one parent root only after inequality, and accepted==n-1 breaks before later edges.

Evidence is from `main.jl`, L1,L2,L3,L4,L5,L6,L7,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41,L42.

- L1: `function root!(parents, vertex)`
- L2: `while parents[vertex] != vertex`
- L3: `parents[vertex] = parents[parents[vertex]]`
- L4: `vertex = parents[vertex]`
- L5: `end`
- L6: `return vertex`
- L7: `end`
- L10: `edges = [`
- L11: `('A', 'B', 7),`
- L12: `('C', 'A', 4),`
- L13: `('B', 'C', 9),`
- L14: `('B', 'D', 14),`
- L15: `('D', 'C', 6),`
- L16: `('C', 'E', 3),`
- L17: `('E', 'D', 5),`
- L18: `('F', 'D', 11),`
- L19: `('E', 'G', 16),`
- L20: `('G', 'F', 8),`
- L21: `('H', 'F', 12),`
- L22: `('G', 'H', 2),`
- L23: `('H', 'E', 10),`
- L24: `]`
- L25: `sort!(edges; by = edge -> edge[3])`
- L26: `parents = collect(1:8)`
- L27: `accepted, skipped, total = 0, 0, 0`
- L28: `for (a, b, weight) in edges`
- L29: `first_root = root!(parents, Int(a)-Int('A')+1)`
- L30: `second_root = root!(parents, Int(b)-Int('A')+1)`
- L31: `if first_root == second_root`
- L32: `skipped += 1`
- L33: `else`
- L34: `parents[second_root] = first_root`
- L35: `accepted += 1`
- L36: `total += weight`
- L37: `println(min(a, b), '-', max(a, b), " ", weight)`
- L38: `accepted == 7 && break`
- L39: `end`
- L40: `end`
- L41: `println("total weight: ", total)`
- L42: `println("skipped: ", skipped)`

Minimization: The complete edge data, ordering, root/union decisions, early stop and output totals are necessary for this end-to-end trace. Imports/main wrappers add no relevant behavior. The selected complete original lines, in source order, cost 568 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 574, and the complete source costs 580. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
