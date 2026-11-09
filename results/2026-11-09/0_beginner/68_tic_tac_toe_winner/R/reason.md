# Task B: 68_tic_tac_toe_winner / R

The winner test requires a nonempty first mark and equality of all three values in the selected row/column/diagonal. Its line values do not give a writable alias through which this check changes original board cells. No mutation is performed by the equality test, and the next line check still obtains its intended values from the unchanged board.

Rows/columns/diagonals are numeric/character value vectors in a list, with R copy-on-modify semantics. The equality check only reads them, and no reference-like board object is mutated.

Evidence is from `main.R`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12.

- L1: `outcome <- function(board) {`
- L2: `values <- do.call(rbind, strsplit(board, "", fixed = TRUE))`
- L3: `lines <- c(`
- L4: `lapply(1:3, function(i) values[i, ]),`
- L5: `lapply(1:3, function(i) values[, i]),`
- L6: `list(diag(values), values[cbind(1:3, 3:1)])`
- L7: `)`
- L8: `for (line in lines) {`
- L9: `if (line[1] != "." && all(line == line[1])) {`
- L10: `return(paste(line[1], "wins"))`
- L11: `}`
- L12: `}`

Minimization: Line construction/selection and the complete winner guard are necessary. Actual game output and unrelated board literals add nothing about line storage or aliasing. The selected complete original lines, in source order, cost 189 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 189, and the complete source costs 411. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
