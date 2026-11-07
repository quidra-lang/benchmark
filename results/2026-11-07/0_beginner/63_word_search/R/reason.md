# Task B: 63_word_search / R

For candidate TIGER from logical row 0,column 0 facing E, the word binding is TIGER, starting coordinates are 0,0 and direction offsets are dr=0,dc=1. At offset k the comparison uses row+dr*k,column+dc*k and word[k], after checking board bounds. These are the routine's actual local bindings; row/column arguments and loop-offset variables do not name unrelated global search state.

find_word receives word; board is read from the enclosing/global scope. The routine's local row,column and directions matrix supply the candidate and offsets.

Evidence is from `main.R`, L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25.

- L14: `find_word <- function(word) {`
- L15: `directions <- list(c(0, 1), c(1, 1), c(1, 0), c(1, -1), c(0, -1), c(-1, -1), c(-1, 0), c(-1, 1))`
- L16: `names <- c("E", "SE", "S", "SW", "W", "NW", "N", "NE")`
- L17: `for (row in 0:9) {`
- L18: `for (column in 0:9) {`
- L19: `for (d in seq_along(directions)) {`
- L20: `matched <- TRUE`
- L21: `for (offset in 0:(nchar(word) - 1)) {`
- L22: `r <- row + offset * directions[[d]][1]`
- L23: `c_value <- column + offset * directions[[d]][2]`
- L24: `if (r < 0 || r >= 10 || c_value < 0 || c_value >= 10 ||`
- L25: `substr(board[r + 1], c_value + 1, c_value + 1) != substr(word, offset + 1, offset + 1)) {`

Minimization: The function/argument bindings, E offset representation and candidate coordinate/comparison block suffice. Full board data and the whole search traversal are outside this local name-resolution question. The selected complete original lines, in source order, cost 376 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 376, and the complete source costs 604. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
