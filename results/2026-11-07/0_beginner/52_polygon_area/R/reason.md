# Task B: 52_polygon_area / R

For an empty vertex sequence the edge loop has zero iterations. Therefore neither the first vertex access nor the last-to-first/wrap access inside its body is evaluated; there is no prior first-vertex read and no explicit rejection. The initialized twice-area/cross-sum 0 and perimeter 0.0 reach formatting, giving polygon 1 area=0.0 and perimeter=0.000. These are default results, not a validation error.

seq_len(nrow(vertices)) is integer(0), so both indexed endpoint reads and wrap calculation are skipped; defaults flow to sprintf.

Evidence is from `main.R`, L7,L8,L9,L10,L11,L12,L13,L14,L15,L20,L21.

- L7: `vertices <- polygons[[number]]`
- L8: `twice_area <- 0L`
- L9: `perimeter <- 0`
- L10: `for (i in seq_len(nrow(vertices))) {`
- L11: `j <- i %% nrow(vertices) + 1`
- L12: `x <- vertices[i, 1]`
- L13: `y <- vertices[i, 2]`
- L14: `next_x <- vertices[j, 1]`
- L15: `next_y <- vertices[j, 2]`
- L20: `}`
- L21: `cat(sprintf("polygon %d: area=%.1f perimeter=%.3f\n", number, abs(twice_area) / 2, perimeter))`

Minimization: Initialization, loop entry, the endpoint accesses and loop exit/output are enough to determine empty behavior. Edge arithmetic inside the skipped body and actual nonempty polygon literals are unnecessary. The selected complete original lines, in source order, cost 171 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 254, and the complete source costs 455. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
