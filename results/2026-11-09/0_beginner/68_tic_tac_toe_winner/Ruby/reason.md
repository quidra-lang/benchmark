For board 6, a row or diagonal check reads the intended original cells without mutating the board. Its rows XOX/OXO/OXX have no row win, while the main diagonal gives XXX and a winner X. The line representation and test are read-only during these checks.

board.dup copies only the outer row array, so its initial row strings remain shared references; the diagonal map/join creates a new string. The winner test only reads line and creates chars/uniq arrays, so shared row strings are never mutated.

The sixth board, row/diagonal access construction and equality test establish original cell reads and X on the main diagonal. No assignment to board storage occurs in those operations.
