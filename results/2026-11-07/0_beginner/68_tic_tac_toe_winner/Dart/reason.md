For board 6, a row or diagonal check reads the intended original cells without mutating the board. Its rows XOX/OXO/OXX have no row win, while the main diagonal gives XXX and a winner X. The line representation and test are read-only during these checks.

boards[i].join creates the immutable cells string. lines contains independent const integer index lists; the loop reads cells at those indices and never writes either representation. No deep-copy assumption is required.

The sixth board, row/diagonal access construction and equality test establish original cell reads and X on the main diagonal. No assignment to board storage occurs in those operations.
