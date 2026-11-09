Row 0 is [1] and row 1 is [1,1]. Endpoint ones are supplied explicitly; no interior addition is attempted for the single-element preceding row, so no nonexistent neighboring pair is read.

n=0 creates a length-one all-ones row and saves it as previous. At n=1, List.filled(2,1) supplies both endpoints and k<n with k=1 rejects all interior reads.

The initial row, explicit endpoints and interior-iteration bounds establish rows zero and one without indexing an absent neighboring pair. Later rows add no evidence for that base transition.
