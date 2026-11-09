Derive every next cell from the unchanged current board: count only eight in-bounds neighbors, then make a cell alive for count 3 or for an already-live cell with count 2. The corner rejects the proposed (-1,0) before indexing. Store all outputs separately and replace board only after the complete traversal.

List.generate creates separate next rows. continue excludes the center; short-circuit && rejects rr<0 before indexing. next[r][c] writes a separate matrix and board=next occurs after both cell loops.

Current-board reads, neighbor bounds/count, birth/survival condition, separate output storage and final board replacement establish synchronous evolution. Output rendering cannot establish that isolation.
