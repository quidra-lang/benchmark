For board 6, a row or diagonal check reads the intended original cells without mutating the board. Its rows XOX/OXO/OXX have no row win, while the main diagonal gives XXX and a winner X. The line representation and test are read-only during these checks.

The lines table is a new outer table containing immutable row strings. The diagonal concatenation constructs another string; sub and string.rep compare values without mutation. Each next check still reads the same board.

The sixth board, row/diagonal access construction and equality test establish original cell reads and X on the main diagonal. No assignment to board storage occurs in those operations.
