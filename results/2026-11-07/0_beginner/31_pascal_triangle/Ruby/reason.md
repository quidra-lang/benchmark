Row 0 is [1] and row 1 is [1,1]. Endpoint ones are supplied explicitly; no interior addition is attempted for the single-element preceding row, so no nonexistent neighboring pair is read.

[1] + row.each_cons(2).map(&:sum) + [1] supplies endpoints and an empty interior because each_cons(2) yields nothing for [1].

The initial row, explicit endpoints and interior-iteration bounds establish rows zero and one without indexing an absent neighboring pair. Later rows add no evidence for that base transition.
