line_label <- function(row, index) paste0(if (row) "R" else "C", index)
line_cells <- function(grid, row, index) if (row) grid[index, ] else grid[, index]
determined_count <- function(grid) sum(grid != UNKNOWN)
step_text <- function(step) paste0(line_label(step$row, step$index), if (step$contradiction) "!" else paste0("+", step$gain))
propagate <- function(grid, row_clues, column_clues, precise, row_marks = rep(TRUE, nrow(grid)), column_marks = rep(TRUE, ncol(grid))) {
  steps <- list()
  conflict <- NULL
  while (any(row_marks) || any(column_marks)) {
    row <- any(row_marks)
    index <- which(if (row) row_marks else column_marks)[1L]
    if (row) row_marks[index] <- FALSE else column_marks[index] <- FALSE
    cells <- line_cells(grid, row, index)
    solved <- solve_line(cells, if (row) row_clues[[index]] else column_clues[[index]], precise)
    if (is.null(solved)) {
      conflict <- list(row = row, index = index, gain = 0L, contradiction = TRUE)
      steps[[length(steps) + 1L]] <- conflict
      break
    }
    changed <- which(cells == UNKNOWN & solved != UNKNOWN)
    if (row) {
      grid[index, ] <- solved
      column_marks[changed] <- TRUE
    } else {
      grid[, index] <- solved
      row_marks[changed] <- TRUE
    }
    steps[[length(steps) + 1L]] <- list(row = row, index = index, gain = length(changed), contradiction = FALSE)
  }
  list(grid = grid, steps = steps, conflict = conflict)
}
