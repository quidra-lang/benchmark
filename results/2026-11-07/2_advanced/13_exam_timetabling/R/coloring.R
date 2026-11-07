new_attempt <- function(courses, graph, limit, candidate_slots) {
  list2env(list(courses = courses, graph = graph, limit = limit, candidates = candidate_slots,
    dead_ends = 0L, dead_end_course = NULL, aborted = FALSE, chosen = list()), parent = emptyenv())
}

saturation <- function(attempt, id, assignment) {
  adjacent <- intersect(names(neighbours(attempt$graph, id)), names(assignment))
  length(unique(assignment[adjacent]))
}

attempt_search <- function(attempt, work) {
  remaining <- setdiff(attempt$courses, names(work$assignment))
  if (!length(remaining)) return(TRUE)
  saturations <- vapply(remaining, function(id) saturation(attempt, id, work$assignment), 0L)
  degrees <- vapply(remaining, function(id) degree(attempt$graph, id), 0L)
  id <- remaining[order(-saturations, -degrees, remaining, method = "radix")][1L]
  attempt$chosen[[length(attempt$chosen) + 1L]] <- list(id, saturation(attempt, id, work$assignment))
  for (slot in attempt$candidates(id, work$assignment)) {
    work$assignment[[id]] <- slot
    if (attempt_search(attempt, work)) return(TRUE)
    work$assignment <- work$assignment[names(work$assignment) != id]
    if (attempt$aborted) return(FALSE)
  }
  attempt$chosen <- head(attempt$chosen, -1L)
  attempt$dead_ends <- attempt$dead_ends + 1L
  attempt$dead_end_course <- id
  attempt$aborted <- attempt$dead_ends > attempt$limit
  FALSE
}

greedy_numbering <- function(order, graph) {
  numbers <- setNames(integer(), character())
  for (id in order) {
    taken <- numbers[intersect(names(neighbours(graph, id)), names(numbers))]
    number <- 1L
    while (number %in% taken) number <- number + 1L
    numbers[[id]] <- number
  }
  if (length(numbers)) max(numbers) else 0L
}
