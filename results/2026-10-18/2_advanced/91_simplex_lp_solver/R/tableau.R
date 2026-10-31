new_tableau <- function(form) {
  list2env(list(row_names = form$row_names, column_names = form$column_names,
               values = form$matrix, rhs = form$rhs, basic = form$initial), parent = emptyenv())
}
pivot <- function(tableau, row, column) {
  divisor <- tableau$values[[row]][[column]]
  tableau$values[[row]] <- lapply(tableau$values[[row]], function(value) value / divisor)
  tableau$rhs[[row]] <- tableau$rhs[[row]] / divisor
  for (other in seq_along(tableau$values)) {
    if (other == row) next
    factor <- tableau$values[[other]][[column]]
    tableau$values[[other]] <- Map(function(value, pivot_value) value - factor * pivot_value, tableau$values[[other]], tableau$values[[row]])
    tableau$rhs[[other]] <- tableau$rhs[[other]] - factor * tableau$rhs[[row]]
  }
  tableau$basic[[row]] <- column
}
reduced_costs <- function(tableau, costs) {
  lapply(seq_along(costs), function(column) {
    costs[[column]] - qsum(lapply(seq_along(tableau$basic), function(row) costs[[tableau$basic[[row]]]] * tableau$values[[row]][[column]]))
  })
}
phase_value <- function(tableau, costs) qsum(lapply(seq_along(tableau$basic), function(row) costs[[tableau$basic[[row]]]] * tableau$rhs[[row]]))
join_fractions <- function(values) paste(vapply(values, fraction_text, character(1L)), collapse = " ")
tableau_display <- function(tableau, heading, costs, objective) {
  lines <- c(paste("TABLEAU", heading), paste("COLUMNS", paste(tableau$column_names, collapse = " ")))
  for (row in seq_along(tableau$values)) lines <- c(lines, paste("ROW", tableau$row_names[[row]], tableau$column_names[[tableau$basic[[row]]]], join_fractions(tableau$values[[row]]), "|", fraction_text(tableau$rhs[[row]])))
  c(lines, paste("COST", join_fractions(reduced_costs(tableau, costs)), "|", fraction_text(objective(phase_value(tableau, costs)))))
}
