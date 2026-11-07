new_grid <- function(rows) {
  list(width = nchar(rows[1L]), height = length(rows), cells = unlist(strsplit(rows, "", fixed = TRUE), use.names = FALSE))
}

grid_cell <- function(grid, row, column) row * grid$width + column + 1L
location_text <- function(grid, cell) paste0((cell - 1L) %/% grid$width + 1L, ",", (cell - 1L) %% grid$width + 1L)
is_open <- function(grid, row, column) row >= 0 && row < grid$height && column >= 0 && column < grid$width && grid$cells[grid_cell(grid, row, column)] != "#"
white_cells <- function(grid) which(grid$cells != "#")

asymmetric_cell <- function(grid, symmetry) {
  for (row in seq_len(grid$height) - 1L) {
    for (column in seq_len(grid$width) - 1L) {
      other_row <- if (symmetry == "rot180") grid$height - 1L - row else row
      if (is_open(grid, row, column) != is_open(grid, other_row, grid$width - 1L - column)) return(grid_cell(grid, row, column))
    }
  }
  0L
}

component_count <- function(grid) {
  seen <- rep(FALSE, length(grid$cells))
  count <- 0L
  for (start in white_cells(grid)) {
    if (seen[start]) next
    count <- count + 1L
    seen[start] <- TRUE
    stack <- start
    while (length(stack)) {
      cell <- tail(stack, 1L)
      stack <- head(stack, -1L)
      row <- (cell - 1L) %/% grid$width
      column <- (cell - 1L) %% grid$width
      for (offset in list(c(-1L, 0L), c(1L, 0L), c(0L, -1L), c(0L, 1L))) {
        r <- row + offset[1L]
        next_column <- column + offset[2L]
        if (is_open(grid, r, next_column)) {
          neighbor <- grid_cell(grid, r, next_column)
          if (!seen[neighbor]) {
            seen[neighbor] <- TRUE
            stack <- c(stack, neighbor)
          }
        }
      }
    }
  }
  count
}
