# Task B: 80_graph_traversal / R

The unordered edges build both directions of an undirected graph and neighbors are visited in ascending numeric order. DFS from 0 is `0 2 7 5 3 8`: 7 is first reached recursively from 2. BFS from 0 is `0 2 5 7 3 8`: 7 is first marked/enqueued while expanding 2, and each vertex is marked on discovery so it is queued once. Restart component search at the smallest unseen vertex, sort each discovered component for display, and number components from 1. Components are `0 2 3 5 7 8` and `1 4 6`.

Sorted adjacency lists supply numeric neighbor order; recursive seen state and a queue with head position establish the two traversal orders, then seen resets for components.

Evidence is from `main.R`, L1,L2,L3,L4,L5,L6,L7,L8,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41,L42,L43,L44,L45,L46,L47,L48,L49.

- L1: `adjacency <- replicate(9, integer(0), simplify = FALSE)`
- L2: `for (edge in list(c(5, 0), c(3, 8), c(7, 2), c(1, 6), c(0, 2), c(5, 3), c(7, 5), c(6, 4), c(8, 7))) {`
- L3: `a <- edge[1] + 1`
- L4: `b <- edge[2] + 1`
- L5: `adjacency[[a]] <- c(adjacency[[a]], b - 1)`
- L6: `adjacency[[b]] <- c(adjacency[[b]], a - 1)`
- L7: `}`
- L8: `adjacency <- lapply(adjacency, sort)`
- L10: `walk <- function(start, seen) {`
- L11: `order <- integer(0)`
- L12: `visit <- function(vertex) {`
- L13: `seen[vertex + 1] <<- TRUE`
- L14: `order <<- c(order, vertex)`
- L15: `for (neighbor in adjacency[[vertex + 1]]) {`
- L16: `if (!seen[neighbor + 1]) visit(neighbor)`
- L17: `}`
- L18: `}`
- L19: `visit(start)`
- L20: `list(seen = seen, order = order)`
- L21: `}`
- L23: `cat("DFS: ", paste(walk(0, rep(FALSE, 9))$order, collapse = " "), "\n", sep = "")`
- L24: `queue <- 0`
- L25: `seen <- rep(FALSE, 9)`
- L26: `seen[1] <- TRUE`
- L27: `head_index <- 1`
- L28: `while (head_index <= length(queue)) {`
- L29: `vertex <- queue[head_index]`
- L30: `head_index <- head_index + 1`
- L31: `for (neighbor in adjacency[[vertex + 1]]) {`
- L32: `if (!seen[neighbor + 1]) {`
- L33: `seen[neighbor + 1] <- TRUE`
- L34: `queue <- c(queue, neighbor)`
- L35: `}`
- L36: `}`
- L37: `}`
- L38: `cat("BFS: ", paste(queue, collapse = " "), "\n", sep = "")`
- L39: `seen <- rep(FALSE, 9)`
- L40: `components <- list()`
- L41: `for (vertex in 0:8) {`
- L42: `if (!seen[vertex + 1]) {`
- L43: `result <- walk(vertex, seen)`
- L44: `seen <- result$seen`
- L45: `components[[length(components) + 1]] <- sort(result$order)`
- L46: `}`
- L47: `}`
- L48: `cat(sprintf("components: %d\n", length(components)))`
- L49: `for (i in seq_along(components)) cat(sprintf("component %d: %s\n", i, paste(components[[i]], collapse = " ")))`

Minimization: The graph data/construction, sorted neighbor rule, complete DFS/BFS and restarted component traversal/formatting are necessary for this end-to-end result. Imports and outer wrappers are omitted. The selected complete original lines, in source order, cost 756 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 758, and the complete source costs 758. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
