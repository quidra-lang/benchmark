# Task B: 62_edit_distance / R

At prefix lengths 2,2 the characters are i and i, so replacement cost is zero. The neighboring-prefix candidates are deletion 3, insertion 3 and substitution/match 1; the cell minimum is 1. A character match changes only the replacement cost. The minimum expression still evaluates all three candidates; there is no branch that skips deletion/insertion arithmetic on a match.

ifelse/equality determines cost; min receives all three computed neighbor expressions, so matching does not short-circuit that call.

Evidence is from `main.R`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12.

- L1: `edit_distance <- function(a, b) {`
- L2: `a <- utf8ToInt(a)`
- L3: `b <- utf8ToInt(b)`
- L4: `table <- matrix(0L, length(a) + 1, length(b) + 1)`
- L5: `table[, 1] <- 0:length(a)`
- L6: `table[1, ] <- 0:length(b)`
- L7: `for (i in seq_along(a)) {`
- L8: `for (j in seq_along(b)) {`
- L9: `cost <- as.integer(a[i] != b[j])`
- L10: `table[i + 1, j + 1] <- min(table[i, j + 1] + 1L, table[i + 1, j] + 1L, table[i, j] + cost)`
- L11: `}`
- L12: `}`

Minimization: Initialization, the relevant prefix loops and the cell expression are retained because they establish the concrete neighboring values. No final-distance printing or unrelated string pairs are required. The selected complete original lines, in source order, cost 241 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 241, and the complete source costs 403. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
