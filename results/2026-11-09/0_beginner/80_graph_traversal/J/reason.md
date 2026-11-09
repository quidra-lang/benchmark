# Task B: 80_graph_traversal / J

The unordered edges build both directions of an undirected graph and neighbors are visited in ascending numeric order. DFS from 0 is `0 2 7 5 3 8`: 7 is first reached recursively from 2. BFS from 0 is `0 2 5 7 3 8`: 7 is first marked/enqueued while expanding 2, and each vertex is marked on discovery so it is queued once. Restart component search at the smallest unseen vertex, sort each discovered component for display, and number components from 1. Components are `0 2 3 5 7 8` and `1 4 6`.

The adjacency matrix naturally scans neighbors in numeric index order. The recursive visited array and separate BFS queue/head state establish visit timing.

Evidence is from `main.ijs`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41,L42,L43,L44,L45,L46.

- L1: `dfs =: 3 : 0`
- L2: `'adjacency visited order vertex' =. y`
- L3: `visited =. 1 vertex}visited`
- L4: `order =. order,vertex`
- L5: `for_neighbor. I.vertex{adjacency do.`
- L6: `if. -.neighbor{visited do.`
- L7: `'visited order' =. dfs adjacency;visited;order;neighbor`
- L8: `end.`
- L9: `end.`
- L10: `visited;order`
- L11: `)`
- L13: `adjacency =. 9 9$0`
- L14: `for_edge. 9 2$5 0 3 8 7 2 1 6 0 2 5 3 7 5 6 4 8 7 do.`
- L15: `'a b' =. edge`
- L16: `adjacency =. 1 (<a,b)}adjacency`
- L17: `adjacency =. 1 (<b,a)}adjacency`
- L18: `end.`
- L19: `'visited order' =. dfs adjacency;(9$0);(i.0);0`
- L20: `smoutput 'DFS: ',":order`
- L21: `visited =. 1,8$0`
- L22: `queue =. ,0`
- L23: `head =. 0`
- L24: `order =. i.0`
- L25: `while. head<#queue do.`
- L26: `vertex =. head{queue`
- L27: `head =. >:head`
- L28: `order =. order,vertex`
- L29: `for_neighbor. I.vertex{adjacency do.`
- L30: `if. -.neighbor{visited do.`
- L31: `visited =. 1 neighbor}visited`
- L32: `queue =. queue,neighbor`
- L33: `end.`
- L34: `end.`
- L35: `end.`
- L36: `smoutput 'BFS: ',":order`
- L37: `visited =. 9$0`
- L38: `components =. 0$<i.0`
- L39: `for_vertex. i.9 do.`
- L40: `if. -.vertex{visited do.`
- L41: `'visited order' =. dfs adjacency;visited;(i.0);vertex`
- L42: `components =. components,</:~order`
- L43: `end.`
- L44: `end.`
- L45: `smoutput 'components: ',":#components`
- L46: `for_i. i.#components do. smoutput 'component ',(":>:i),': ',":>i{components end.`

Minimization: The graph data/construction, sorted neighbor rule, complete DFS/BFS and restarted component traversal/formatting are necessary for this end-to-end result. Imports and outer wrappers are omitted. The selected complete original lines, in source order, cost 522 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 532, and the complete source costs 539. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
