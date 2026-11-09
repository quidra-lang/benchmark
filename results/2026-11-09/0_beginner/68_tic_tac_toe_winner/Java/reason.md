# Task B selection: 68_tic_tac_toe_winner / Java

Rows are joined into a new immutable cells string; line entries are index sequences selecting three characters from that string. The winner predicate only reads those indices and cells, without modifying the board or even writing the line-index arrays/lists. References/views to an index list do not imply a deep board copy, but no such copy is required for later checks to keep reading the intended immutable cells.

Keep the line representation, flattening and predicate. Board literals and outcome/output stages are unnecessary because this asks about representation and mutation, not the final winner.

Selected complete source lines in `Main.java`: 7, 9, 10, 11, 12, 13, 14. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
