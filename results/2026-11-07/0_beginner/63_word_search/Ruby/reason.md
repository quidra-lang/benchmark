For candidate TIGER at row 0,column 0,E, the local start coordinates are zero and the direction offsets are (0,1). The comparison derives each cell from the current character offset and the same current word; the board is supplied by enclosing scope rather than copied into the candidate.

word is the lambda parameter supplied by find.call(word); row and column are nested iteration bindings and dr,dc destructure directions. The lambda captures board and uses char/i from word.chars.each_with_index.

The candidate call, coordinate/direction bindings and indexed comparison establish which word and board cells are read. Rendering found words is outside that binding-use question.
