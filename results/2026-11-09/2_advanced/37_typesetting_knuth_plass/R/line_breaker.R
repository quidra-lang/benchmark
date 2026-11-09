line_class <- function(
    slack,
    last
) if (last) 1L else if (slack <= 1L) 0L else if (slack <= 3L) 1L else if (slack <= 6L) 2L else 3L
line_cost <- function(metrics, start, stop, previous_class, params) {
  slack <- metrics_slack(metrics, start, stop)
  last <- stop == metrics$count
  current_class <- line_class(slack, last)
  cost <- params$line_penalty + if (slack < 0L) params$overfull_penalty else if (last) 0L else slack * slack
  if (metrics$breaks[[stop + 1L]]$midword) {
    cost <- cost + params$hyphen_penalty
    if (metrics$breaks[[start + 1L]]$midword) cost <- cost + params$double_hyphen_demerit
  }
  if (last && metrics$breaks[[start + 1L]]$midword) cost <- cost + params$final_hyphen_demerit
  if (abs(current_class - previous_class) >= 2L) cost <- cost + params$fitness_demerit
  cost
}
breaking_cost <- function(metrics, breaking, params) {
  total <- 0L
  start <- 0L
  previous_class <- 1L
  for (stop in breaking) {
    total <- total + line_cost(metrics, start, stop, previous_class, params)
    previous_class <- line_class(metrics_slack(metrics, start, stop), stop == metrics$count)
    start <- stop
  }
  total
}
knuth_plass <- function(metrics, params) {
  states <- lapply(seq_len(metrics$count + 1L), function(i) vector("list", 4L))
  states[[1L]][[2L]] <- c(0L, 0L, 0L)
  for (stop in seq_len(metrics$count)) {
    for (start in seq.int(stop - 1L, 0L)) {
      slack <- metrics_slack(metrics, start, stop)
      if (slack < 0L && stop != start + 1L) break
      current_class <- line_class(slack, stop == metrics$count)
      for (previous_class in 0L:3L) {
        previous <- states[[start + 1L]][[previous_class + 1L]]
        if (is.null(previous)) next
        cost <- previous[[1L]] + line_cost(metrics, start, stop, previous_class, params)
        candidate <- c(cost, start, previous_class)
        best <- states[[stop + 1L]][[current_class + 1L]]
        different <- if (is.null(best)) integer() else which(candidate != best)
        if (is.null(best) || (length(different) && candidate[[different[[1L]]]] < best[[different[[1L]]]])) states[[stop + 1L]][[current_class + 1L]] <- candidate
      }
    }
  }
  breaking <- integer()
  position <- metrics$count
  current_class <- 1L
  cost <- states[[position + 1L]][[current_class + 1L]][[1L]]
  while (position > 0L) {
    breaking <- c(position, breaking)
    previous <- states[[position + 1L]][[current_class + 1L]]
    position <- previous[[2L]]
    current_class <- previous[[3L]]
  }
  list(breaking = breaking, cost = cost)
}
greedy <- function(metrics, params) {
  breaking <- integer()
  start <- 0L
  while (start < metrics$count) {
    chosen <- start + 1L
    if (metrics_slack(metrics, start, chosen) >= 0L && chosen < metrics$count) {
      for (stop in seq.int(chosen + 1L, metrics$count)) {
        if (metrics_slack(metrics, start, stop) < 0L) break
        chosen <- stop
      }
    }
    breaking <- c(breaking, chosen)
    start <- chosen
  }
  list(breaking = breaking, cost = breaking_cost(metrics, breaking, params))
}
break_text <- function(
    metrics,
    method,
    params
) if (method == "kp") knuth_plass(metrics, params) else greedy(metrics, params)
