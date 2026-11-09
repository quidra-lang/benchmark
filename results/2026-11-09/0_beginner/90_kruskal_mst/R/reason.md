# Task B: 90_kruskal_mst / R

Sort all thirteen edges by ascending weight and normalize displayed endpoint names alphabetically. Accept GH:2,CE:3,AC:4,DE:5,AB:7,FG:8,EH:10, totaling 39. At weight 5, D and E are in different components and union succeeds; at weight 6, D and C already share a component, so DC is rejected. BC:9 is the other rejection. EH:10 is the seventh accepted edge, so the n-1 stop occurs immediately and later edges (starting DF:11) are not examined; skipped=2.

The root helper and parent vector supply Union-Find identities; the accepted-size guard terminates the sorted loop before the remaining edges.

Evidence is from `main.R`, L1,L2,L3,L4,L5,L6,L7,L9,L10,L11,L12,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34.

- L1: `edges <- data.frame(`
- L2: `from = c("A", "C", "B", "B", "D", "C", "E", "F", "E", "G", "H", "G", "H"),`
- L3: `to = c("B", "A", "C", "D", "C", "E", "D", "D", "G", "F", "F", "H", "E"),`
- L4: `weight = c(7, 4, 9, 14, 6, 3, 5, 11, 16, 8, 12, 2, 10)`
- L5: `)`
- L6: `edges <- edges[order(edges$weight), ]`
- L7: `parents <- setNames(LETTERS[1:8], LETTERS[1:8])`
- L9: `find_root <- function(vertex) {`
- L10: `while (parents[vertex] != vertex) vertex <- unname(parents[vertex])`
- L11: `vertex`
- L12: `}`
- L14: `accepted <- 0`
- L15: `skipped <- 0`
- L16: `total <- 0`
- L17: `for (edge in seq_len(nrow(edges))) {`
- L18: `a <- edges$from[edge]`
- L19: `b <- edges$to[edge]`
- L20: `weight <- edges$weight[edge]`
- L21: `first_root <- find_root(a)`
- L22: `second_root <- find_root(b)`
- L23: `if (first_root == second_root) {`
- L24: `skipped <- skipped + 1`
- L25: `} else {`
- L26: `parents[second_root] <- first_root`
- L27: `accepted <- accepted + 1`
- L28: `total <- total + weight`
- L29: `endpoints <- sort(c(a, b), method = "radix")`
- L30: `cat(sprintf("%s-%s %d\n", endpoints[1], endpoints[2], weight))`
- L31: `if (accepted == 7) break`
- L32: `}`
- L33: `}`
- L34: `cat(sprintf("total weight: %d\nskipped: %d\n", total, skipped))`

Minimization: The complete edge data, ordering, root/union decisions, early stop and output totals are necessary for this end-to-end trace. Imports/main wrappers add no relevant behavior. The selected complete original lines, in source order, cost 569 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 571, and the complete source costs 571. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
