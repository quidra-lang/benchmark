conflict_graph <- function(vertices, student_courses) {
  vertices <- ascii_sort(vertices)
  shared <- matrix(0L, length(vertices), length(vertices), dimnames = list(vertices, vertices))
  for (ids in student_courses) {
    if (length(ids) < 2L) next
    for (i in seq_len(length(ids) - 1L)) for (j in seq.int(i + 1L, length(ids))) {
      shared[ids[i], ids[j]] <- shared[ids[i], ids[j]] + 1L
      shared[ids[j], ids[i]] <- shared[ids[j], ids[i]] + 1L
    }
  }
  list(vertices = vertices, shared = shared)
}

neighbours <- function(graph, id) {
  if (!id %in% graph$vertices) return(setNames(integer(), character()))
  values <- graph$shared[id, , drop = TRUE]
  names(values) <- graph$vertices
  values[values > 0L]
}
degree <- function(graph, id) length(neighbours(graph, id))
shared_total <- function(graph, id) sum(neighbours(graph, id))

graph_edges <- function(graph) {
  result <- list()
  for (first in graph$vertices) for (second in names(neighbours(graph, first))) {
    if (match(first, graph$vertices) < match(second, graph$vertices)) result[[length(result) + 1L]] <- list(first, second, graph$shared[first, second])
  }
  result
}

graph_components <- function(graph) {
  seen <- character()
  result <- list()
  for (vertex in graph$vertices) {
    if (vertex %in% seen) next
    seen <- c(seen, vertex)
    component <- vertex
    index <- 1L
    while (index <= length(component)) {
      added <- setdiff(names(neighbours(graph, component[index])), seen)
      seen <- c(seen, added)
      component <- c(component, added)
      index <- index + 1L
    }
    result[[length(result) + 1L]] <- ascii_sort(component)
  }
  result[order(-lengths(result), vapply(result, `[`, "", 1L), method = "radix")]
}

greedy_clique <- function(graph, candidates) {
  result <- character()
  while (length(candidates)) {
    chosen <- candidates[order(-vapply(candidates, function(id) degree(graph, id), 0L), candidates, method = "radix")][1L]
    result <- c(result, chosen)
    candidates <- candidates[candidates %in% names(neighbours(graph, chosen))]
  }
  result
}

kempe_chain <- function(graph, assignment, start, home, target) {
  chain <- start
  index <- 1L
  while (index <= length(chain)) {
    adjacent <- setdiff(names(neighbours(graph, chain[index])), chain)
    added <- adjacent[adjacent %in% names(assignment) & assignment[adjacent] %in% c(home, target)]
    chain <- c(chain, added)
    index <- index + 1L
  }
  ascii_sort(chain)
}

reachable <- function(arrows, source, target) {
  stack <- seen <- source
  while (length(stack)) {
    node <- stack[length(stack)]
    stack <- stack[-length(stack)]
    if (identical(node, target)) return(TRUE)
    added <- setdiff(arrows[[node]], seen)
    seen <- c(seen, added)
    stack <- c(stack, added)
  }
  FALSE
}
