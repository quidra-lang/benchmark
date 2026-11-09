Row 0 is [1] and row 1 is [1,1]. Endpoint ones are supplied explicitly; no interior addition is attempted for the single-element preceding row, so no nonexistent neighboring pair is read.

next_row begins with 1, the k=2..#row loop is empty when #row=1, and index #row+1 receives the second endpoint. row is rebound only after construction.

The initial row, explicit endpoints and interior-iteration bounds establish rows zero and one without indexing an absent neighboring pair. Later rows add no evidence for that base transition.
