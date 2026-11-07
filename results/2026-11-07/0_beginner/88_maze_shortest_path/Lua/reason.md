Coordinate pairs must be the uniform stored parent value, including the start marker, and reconstruction must read that same representation. Preserve discovery order and keys if desired; change the value at first discovery and the reconstruction conversion together rather than changing only one side.

The source already satisfies the contract: start, queue entries and cell are row/column tables; parents[position]=cell stores that pair and reconstruction reads it via key(r,c). The string lookup key is independent of the stored pair value.

Parent initialization, first-discovery assignment and reconstruction reads are the coupled representation sites. Unchanged BFS neighbor order/output labels need no rewrite.
