# Task B: 86_convex_hull / R

First sort coordinate pairs lexicographically, then traverse that sorted collection in reverse; the first two points are (8,4) and (7,-1). For each candidate, compare it with the last two chain points via the signed cross product. While chain length permits and cross<=0, remove the last chain point repeatedly, then append the current point. The reversal applies to coordinate-sorted order, not the original input order. Stop after the upper chain is built.

The points matrix is coordinate-ordered before its rows become a list; chain(rev(points)) uses the sorted list and repeatedly removes its last point on cross<=0.

Evidence is from `main.R`, L1,L3,L4,L5,L6,L7,L8,L9,L10,L11,L14,L15,L16,L17,L18,L19,L21.

- L1: `cross_product <- function(o, a, b) (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1])`
- L3: `chain <- function(points) {`
- L4: `result <- list()`
- L5: `for (point in points) {`
- L6: `while (length(result) >= 2 && cross_product(result[[length(result) - 1]], tail(result, 1)[[1]], point) <= 0) {`
- L7: `result <- head(result, -1)`
- L8: `}`
- L9: `result[[length(result) + 1]] <- point`
- L10: `}`
- L11: `result`
- L14: `points <- matrix(as.integer(c(`
- L15: `3, 2, -6, 1, 8, 4, 0, 0, -3, 7, 4, -3, 1, -5, -2, 1, 5, 6, -6, -2, 2, -2, 7, -1, -3, 4, 2, 8, -6,`
- L16: `3`
- L17: `)), ncol = 2, byrow = TRUE)`
- L18: `points <- points[order(points[, 1], points[, 2]), ]`
- L19: `point_list <- lapply(seq_len(nrow(points)), function(i) points[i, ])`
- L21: `upper <- chain(rev(point_list))`

Minimization: Cross product, full small chain helper, point data/sort and upper call are required to establish reverse order and repeated removal. Lower-chain concatenation, area and output are omitted. The selected complete original lines, in source order, cost 412 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 427, and the complete source costs 639. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
