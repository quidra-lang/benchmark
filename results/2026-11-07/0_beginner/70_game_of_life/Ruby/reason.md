Derive every next cell from the unchanged current board: count only eight in-bounds neighbors, then make a cell alive for count 3 or for an already-live cell with count 2. The corner rejects the proposed (-1,0) before indexing. Store all outputs separately and replace board only after the complete traversal.

Short-circuit && tests displacement and bounds before board[r][c]. Fresh next_board rows receive new strings while all neighbor reads use board; the final assignment commits the generation.

Current-board reads, neighbor bounds/count, birth/survival condition, separate output storage and final board replacement establish synchronous evolution. Output rendering cannot establish that isolation.
