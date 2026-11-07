For candidate TIGER at row 0,column 0,E, the local start coordinates are zero and the direction offsets are (0,1). The comparison derives each cell from the current character offset and the same current word; the board is supplied by enclosing scope rather than copied into the candidate.

word is the find_word parameter, row/column are local numeric for variables, and direction is the current table entry with offsets in cells 2,3. board is an outer local captured by the function; logical r,c translate by +1 for physical access.

The candidate call, coordinate/direction bindings and indexed comparison establish which word and board cells are read. Rendering found words is outside that binding-use question.
