Derive every next cell from the unchanged current board: count only eight in-bounds neighbors, then make a cell alive for count 3 or for an already-live cell with count 2. The corner rejects the proposed (-1,0) before indexing. Store all outputs separately and replace board only after the complete traversal.

following and its rows are fresh tables; board remains the read source. The one-based corner is (1,1), so the corresponding outward physical row 0 fails r>=1 before board[r][c] is reached.

Current-board reads, neighbor bounds/count, birth/survival condition, separate output storage and final board replacement establish synchronous evolution. Output rendering cannot establish that isolation.
