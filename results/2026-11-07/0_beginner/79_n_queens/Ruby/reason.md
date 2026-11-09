Try columns n-1 down to 0 at every row. For size eight, the new first solution has zero-based columns [7,3,0,2,5,1,6,4], rendering .......Q / ...Q.... / Q....... / ..Q..... / .....Q.. / .Q...... / ......Q. / ....Q.... It is the vertical reflection of the ascending-order first solution. All candidate placements remain exhaustively considered, so counts for N=4..8 remain 2,10,4,40,92.

Replace n.times with descending iteration. placement length determines the row, previous columns reject column/diagonal conflicts, push/recursive-call/pop restores each branch, and first receives a copy only once before later traversal mutates placement.

Search initialization, every rejection test, candidate order, restore operation, first-solution capture and renderer establish the changed discovery order. Counts use all solutions, so a first-board-only excerpt is insufficient.
