Coordinate pairs must be the uniform stored parent value, including the start marker, and reconstruction must read that same representation. Preserve discovery order and keys if desired; change the value at first discovery and the reconstruction conversion together rather than changing only one side.

parent is an int list with -1 sentinel and v/u are flattened IDs. Replace parent values with nullable (int,int) records, seed (start~/13,start%13), store (v~/13,v%13) on discovery, update the undiscovered test and unpack/reflatten during reconstruction.

Parent initialization, first-discovery assignment and reconstruction reads are the coupled representation sites. Unchanged BFS neighbor order/output labels need no rewrite.
