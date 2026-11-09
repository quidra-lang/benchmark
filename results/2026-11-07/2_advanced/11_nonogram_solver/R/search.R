guess_cell <- function(grid) {
  rows <- rowSums(grid == UNKNOWN)
  columns <- colSums(grid == UNKNOWN)
  best <- NULL
  best_score <- nrow(grid) + ncol(grid) + 1L
  for (row in seq_len(nrow(grid))) for (column in seq_len(ncol(grid))) if (grid[row, column] == UNKNOWN) {
    score <- rows[row] + columns[column]
    if (score < best_score) {
      best <- c(row, column)
      best_score <- score
    }
  }
  best
}
search_grid <- function(grid, row_clues, column_clues) {
  guesses <- solutions <- list()
  backtracks <- 0L
  visit <- function(grid, depth) {
    cell <- guess_cell(grid)
    for (value in c(FILLED, EMPTY)) {
      child <- grid
      child[cell[1L], cell[2L]] <- value
      rows <- rep(FALSE, nrow(grid))
      columns <- rep(FALSE, ncol(grid))
      rows[cell[1L]] <- columns[cell[2L]] <- TRUE
      propagation <- propagate(child, row_clues, column_clues, TRUE, rows, columns)
      child <- propagation$grid
      known <- determined_count(child)
      if (!is.null(propagation$conflict)) {
        result <- paste0("contradiction at=", line_label(propagation$conflict$row, propagation$conflict$index))
        backtracks <<- backtracks + 1L
      } else if (known == length(child)) {
        solutions[[length(solutions) + 1L]] <<- child
        result <- paste0("solution", length(solutions))
      } else result <- "open"
      guesses[[length(guesses) + 1L]] <<- list(number = length(guesses) + 1L, depth = depth, row = cell[1L], column = cell[2L], value = value, solves = length(propagation$steps), known = known, result = result)
      if (result == "open") {
        if (visit(child, depth + 1L)) return(TRUE)
      } else if (length(solutions) == 2L) return(TRUE)
    }
    FALSE
  }
  visit(grid, 1L)
  list(guesses = guesses, solutions = solutions, backtracks = backtracks,
       max_depth = max(vapply(guesses, function(guess) guess$depth, integer(1L))), line_solves = sum(vapply(guesses, function(guess) guess$solves, integer(1L))))
}
