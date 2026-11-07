Coordinate pairs must be the uniform stored parent value, including the start marker, and reconstruction must read that same representation. Preserve discovery order and keys if desired; change the value at first discovery and the reconstruction conversion together rather than changing only one side.

Keys and current cell are flattened numbers; parent[neighbor]=cell and parent[start]=start store them. Store [row,column] pairs instead, seed a matching start pair and unpack/reflatten the parent during reconstruction (or carry pairs consistently).

Parent initialization, first-discovery assignment and reconstruction reads are the coupled representation sites. Unchanged BFS neighbor order/output labels need no rewrite.
