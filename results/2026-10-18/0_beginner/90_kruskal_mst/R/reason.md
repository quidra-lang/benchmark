# Task B selection: 90_kruskal_mst / R

## Common answer requirements

Trace weight-5 acceptance and weight-6 rejection using components; identify final accepted edge and completion stop; explain exactly which examined edges increment skipped.

## Answer and source dependencies

Weight order first accepts G-H (2), C-E (3), A-C (4). E-D (5) joins the {A,C,E} component to D, so it is accepted. D-C (6) then has equal roots and is rejected, incrementing skipped. A-B (7) and F-G (8) join distinct components; B-C (9) is another equal-root rejection. E-H (10) is the final accepted edge joining {A,B,C,D,E} to {F,G,H}. Accepted reaches seven for eight vertices and the loop stops. Skipped is two, counting only the examined cycle edges 6 and 9. Edges after completion never reach the root comparison/increment and cannot increase skipped. Root chasing/compression preserves component identity; linking two roots merges components.



## Scope and dependency evidence checked after independent review

The root helper must finish its chase/compression before returning the representative. The cycle-rejection branch ends before root linking and accepted increment, so equal roots increment only skipped and continue. Required edge declaration/endpoint-to-letter mapping associates the recorded weight5,6 and final10 decisions with the actual graph; later unexamined edges do not execute rejection logic.

Source: `main.R`. Selected original locations: L1,L2,L3,L4,L6,L7,L9,L10,L11,L12,L14,L15,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L31.

- L1: `edges <- data.frame(` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `  from = c("A", "C", "B", "B", "D", "C", "E", "F", "E", "G", "H", "G", "H"),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `  to = c("B", "A", "C", "D", "C", "E", "D", "D", "G", "F", "F", "H", "E"),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `  weight = c(7, 4, 9, 14, 6, 3, 5, 11, 16, 8, 12, 2, 10)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `edges <- edges[order(edges$weight), ]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `parents <- setNames(LETTERS[1:8], LETTERS[1:8])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `find_root <- function(vertex) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `  while (parents[vertex] != vertex) vertex <- unname(parents[vertex])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `  vertex` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L14: `accepted <- 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `skipped <- 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `for (edge in seq_len(nrow(edges))) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `  a <- edges$from[edge]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `  b <- edges$to[edge]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `  weight <- edges$weight[edge]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `  first_root <- find_root(a)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `  second_root <- find_root(b)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `  if (first_root == second_root) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `    skipped <- skipped + 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `  } else {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `    parents[second_root] <- first_root` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `    accepted <- accepted + 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `    if (accepted == 7) break` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **458 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 456 tokens. The contiguous original span L1–L31 costs 536 tokens; the complete original source costs 571 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 449 tokens; removes `edges <- data.frame(` from the dependency chain described above.
- Without L2: 385 tokens; removes `from = c("A", "C", "B", "B", "D", "C", "E", "F", "E", "G", "H", "G", "H"),` from the dependency chain described above.
- Without L3: 385 tokens; removes `to = c("B", "A", "C", "D", "C", "E", "D", "D", "G", "F", "F", "H", "E"),` from the dependency chain described above.
- Without L4: 407 tokens; removes `weight = c(7, 4, 9, 14, 6, 3, 5, 11, 16, 8, 12, 2, 10)` from the dependency chain described above.
- Without L6: 442 tokens; removes `edges <- edges[order(edges$weight), ]` from the dependency chain described above.
- Without L7: 435 tokens; removes `parents <- setNames(LETTERS[1:8], LETTERS[1:8])` from the dependency chain described above.
- Without L9: 445 tokens; removes `find_root <- function(vertex) {` from the dependency chain described above.
- Without L10: 432 tokens; removes `while (parents[vertex] != vertex) vertex <- unname(parents[vertex])` from the dependency chain described above.
- Without L11: 455 tokens; removes `vertex` from the dependency chain described above.
- Without L12: 456 tokens; removes `}` from the dependency chain described above.
- Without L14: 452 tokens; removes `accepted <- 0` from the dependency chain described above.
- Without L15: 452 tokens; removes `skipped <- 0` from the dependency chain described above.
- Without L17: 438 tokens; removes `for (edge in seq_len(nrow(edges))) {` from the dependency chain described above.
- Without L18: 446 tokens; removes `a <- edges$from[edge]` from the dependency chain described above.
- Without L19: 446 tokens; removes `b <- edges$to[edge]` from the dependency chain described above.
- Without L20: 446 tokens; removes `weight <- edges$weight[edge]` from the dependency chain described above.
- Without L21: 444 tokens; removes `first_root <- find_root(a)` from the dependency chain described above.
- Without L22: 444 tokens; removes `second_root <- find_root(b)` from the dependency chain described above.
- Without L23: 441 tokens; removes `if (first_root == second_root) {` from the dependency chain described above.
- Without L24: 447 tokens; removes `skipped <- skipped + 1` from the dependency chain described above.
- Without L25: 451 tokens; removes `} else {` from the dependency chain described above.
- Without L26: 444 tokens; removes `parents[second_root] <- first_root` from the dependency chain described above.
- Without L27: 447 tokens; removes `accepted <- accepted + 1` from the dependency chain described above.
- Without L31: 445 tokens; removes `if (accepted == 7) break` from the dependency chain described above.
