Accept G-H 2, C-E 3, A-C 4, D-E 5, A-B 7, F-G 8, E-H 10 in that order. Weight 5 joins components, while C-D weight 6 connects already united vertices and is skipped; B-C weight 9 is the other skip. The seventh accepted edge E-H unites the last components, stopping immediately with total weight 39 and skipped 2; later edges are unexamined.

The edge data, ascending sort, path-compressing find and root-equality test establish all decisions. accepted stops at vertices.length-1=7; sorted endpoint names normalize each displayed edge.

Sorted edges, component find/union, skip count, accepted count/termination and total output establish the accepted/skipped order. Edges after the seventh acceptance are irrelevant except as source data establishing they remain unexamined.
