For candidate TIGER at row 0,column 0,E, the local start coordinates are zero and the direction offsets are (0,1). The comparison derives each cell from the current character offset and the same current word; the board is supplied by enclosing scope rather than copied into the candidate.

All loops are inline inside main: word,r,c,d,k are nested local bindings. directions[d] supplies offsets and board is the enclosing const. rr,cc locate the original board cell and word[k] supplies the compared letter.

The candidate call, coordinate/direction bindings and indexed comparison establish which word and board cells are read. Rendering found words is outside that binding-use question.
