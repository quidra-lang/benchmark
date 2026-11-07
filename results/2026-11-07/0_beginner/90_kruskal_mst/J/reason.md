# Task B: 90_kruskal_mst / J

Sort all thirteen edges by ascending weight and normalize displayed endpoint names alphabetically. Accept GH:2,CE:3,AC:4,DE:5,AB:7,FG:8,EH:10, totaling 39. At weight 5, D and E are in different components and union succeeds; at weight 6, D and C already share a component, so DC is rejected. BC:9 is the other rejection. EH:10 is the seventh accepted edge, so the n-1 stop occurs immediately and later edges (starting DF:11) are not examined; skipped=2.

The root helper follows parent values, the loop unions distinct roots and stops once seven edges have been accepted.

Evidence is from `main.ijs`, L1,L2,L3,L4,L5,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24.

- L1: `root =: 3 : 0`
- L2: `vertex =. y`
- L3: `while. vertex~:vertex{parent do. vertex =. vertex{parent end.`
- L4: `vertex`
- L5: `)`
- L7: `names =. 'ABCDEFGH'`
- L8: `edges =. 13 3$0 1 7 2 0 4 1 2 9 1 3 14 3 2 6 2 4 3 4 3 5 5 3 11 4 6 16 6 5 8 7 5 12 6 7 2 7 4 10`
- L9: `edges =. edges {~ /:2{"1 edges`
- L10: `parent =: i.8`
- L11: `accepted =. skipped =. total =. 0`
- L12: `for_edge. edges do.`
- L13: `'a b weight' =. edge`
- L14: `first =. root a`
- L15: `second =. root b`
- L16: `if. first=second do. skipped =. >:skipped continue. end.`
- L17: `parent =: first second}parent`
- L18: `smoutput ((a<.b){names),'-',((a>.b){names),' ',":weight`
- L19: `total =. total+weight`
- L20: `accepted =. >:accepted`
- L21: `if. accepted=7 do. break. end.`
- L22: `end.`
- L23: `smoutput 'total weight: ',":total`
- L24: `smoutput 'skipped: ',":skipped`

Minimization: The complete edge data, ordering, root/union decisions, early stop and output totals are necessary for this end-to-end trace. Imports/main wrappers add no relevant behavior. The selected complete original lines, in source order, cost 354 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 364, and the complete source costs 371. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
