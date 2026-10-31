# Task B selection: 86_convex_hull / R

## Common answer requirements

Trace the three x=-6 points in sorted forward/reverse chains; identify collinear rejection cross comparison; explain endpoint removal and concatenation establishing lexicographic start and counterclockwise order.

## Answer and source dependencies

Sorting by x then y presents (-6,-2), (-6,1), (-6,3) to the lower chain. The third gives cross product zero, so the middle point is popped; a later point to their right also removes (-6,3) from the lower chain. The reversed upper scan encounters (-6,3), then (-6,1), then (-6,-2); again the zero-cross rule removes the middle boundary point. The <=0 pop comparison removes clockwise and collinear turns, retaining strictly counterclockwise corners. Each completed chain shares its two endpoints with the other. Omitting each chain’s final endpoint and concatenating lower then upper includes each shared endpoint once, begins at lexicographically smallest (-6,-2), and goes counterclockwise around the hull.



## Scope and dependency evidence checked after independent review

Point record/tuple field associations establish which supplied coordinate is x and which is y. Cross/comparator/chain definitions terminate before their uses; each pop loop ends before the new point is appended, each chain traversal ends before return or joining, and the x-sort branch ends before its y fallback. Sorted x=-6 points are(-6,-2),(-6,1),(-6,3): cross0 removes the middle point; the next rightward point removes the upper endpoint from the lower chain, while the reverse upper pass retains it and removes the middle collinear point. Dropping each completed chain final endpoint before concatenating lower then upper keeps each extreme once, starts at(-6,-2), and follows counterclockwise order.

Source: `main.R`. Selected original locations: L1,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L14,L15,L16,L17,L18,L19,L20,L21,L22.

- L1: `cross_product <- function(o, a, b) (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `chain <- function(points) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `  result <- list()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `  for (point in points) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `    while (length(result) >= 2 && cross_product(result[[length(result) - 1]], tail(result, 1)[[1]], point) <= 0) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `      result <- head(result, -1)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L9: `    result[[length(result) + 1]] <- point` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `  }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L11: `  result` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L14: `points <- matrix(as.integer(c(` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `  3, 2, -6, 1, 8, 4, 0, 0, -3, 7, 4, -3, 1, -5, -2, 1, 5, 6, -6, -2, 2, -2, 7, -1, -3, 4, 2, 8, -6,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `  3` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `)), ncol = 2, byrow = TRUE)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `points <- points[order(points[, 1], points[, 2]), ]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `point_list <- lapply(seq_len(nrow(points)), function(i) points[i, ])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `lower <- chain(point_list)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `upper <- chain(rev(point_list))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `hull <- c(head(lower, -1), head(upper, -1))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **452 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 444 tokens. The contiguous original span L1–L22 costs 454 tokens; the complete original source costs 640 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 373 tokens; removes `cross_product <- function(o, a, b) (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1])` from the dependency chain described above.
- Without L3: 441 tokens; removes `chain <- function(points) {` from the dependency chain described above.
- Without L4: 443 tokens; removes `result <- list()` from the dependency chain described above.
- Without L5: 439 tokens; removes `for (point in points) {` from the dependency chain described above.
- Without L6: 398 tokens; removes `while (length(result) >= 2 && cross_product(result[[length(result) - 1]], tail(result, 1)[[1]], point) <= 0) {` from the dependency chain described above.
- Without L7: 437 tokens; removes `result <- head(result, -1)` from the dependency chain described above.
- Without L8: 449 tokens; removes `}` from the dependency chain described above.
- Without L9: 435 tokens; removes `result[[length(result) + 1]] <- point` from the dependency chain described above.
- Without L10: 449 tokens; removes `}` from the dependency chain described above.
- Without L11: 449 tokens; removes `result` from the dependency chain described above.
- Without L12: 450 tokens; removes `}` from the dependency chain described above.
- Without L14: 439 tokens; removes `points <- matrix(as.integer(c(` from the dependency chain described above.
- Without L15: 353 tokens; removes `3, 2, -6, 1, 8, 4, 0, 0, -3, 7, 4, -3, 1, -5, -2, 1, 5, 6, -6, -2, 2, -2, 7, -1, -3, 4, 2, 8, -6,` from the dependency chain described above.
- Without L16: 449 tokens; removes `3` from the dependency chain described above.
- Without L17: 434 tokens; removes `)), ncol = 2, byrow = TRUE)` from the dependency chain described above.
- Without L18: 425 tokens; removes `points <- points[order(points[, 1], points[, 2]), ]` from the dependency chain described above.
- Without L19: 420 tokens; removes `point_list <- lapply(seq_len(nrow(points)), function(i) points[i, ])` from the dependency chain described above.
- Without L20: 441 tokens; removes `lower <- chain(point_list)` from the dependency chain described above.
- Without L21: 438 tokens; removes `upper <- chain(rev(point_list))` from the dependency chain described above.
- Without L22: 426 tokens; removes `hull <- c(head(lower, -1), head(upper, -1))` from the dependency chain described above.
