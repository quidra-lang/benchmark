run_phase <- function(tableau, costs, candidates, objective) {
  iterations <- 0L
  lines <- character()
  candidates <- sort(candidates)
  repeat {
    reduced <- reduced_costs(tableau, costs)
    eligible <- candidates[vapply(candidates, function(column) reduced[[column]] < 0, logical(1L))]
    if (!length(eligible)) return(list(iterations = iterations, unbounded = NULL, lines = lines))
    column <- eligible[[1L]]
    row <- NULL
    ratio <- NULL
    for (candidate in seq_along(tableau$values)) {
      value <- tableau$values[[candidate]][[column]]
      if (value <= 0) next
      candidate_ratio <- tableau$rhs[[candidate]] / value
      if (is.null(row) || candidate_ratio < ratio || (candidate_ratio == ratio && tableau$basic[[candidate]] < tableau$basic[[row]])) {
        row <- candidate
        ratio <- candidate_ratio
      }
    }
    if (is.null(row)) return(list(iterations = iterations, unbounded = column, lines = lines))
    leaving <- tableau$basic[[row]]
    before <- reduced[[column]]
    pivot(tableau, row, column)
    iterations <- iterations + 1L
    value <- objective(phase_value(tableau, costs))
    lines <- c(lines, paste("PIVOT", iterations, "enter", tableau$column_names[[column]], "reduced", fraction_text(before), "leave", tableau$column_names[[leaving]], "row", tableau$row_names[[row]], "ratio", fraction_text(ratio), "objective", fraction_text(value)))
  }
}
