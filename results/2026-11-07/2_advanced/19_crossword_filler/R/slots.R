starts_run <- function(grid, row, column, dr, dc) is_open(grid, row, column) && !is_open(grid, row - dr, column - dc)
run_length <- function(grid, row, column, dr, dc) {
  length <- 0L
  while (is_open(grid, row + length * dr, column + length * dc)) length <- length + 1L
  length
}

short_run_error <- function(grid) {
  for (row in seq_len(grid$height) - 1L) {
    for (column in seq_len(grid$width) - 1L) {
      for (across in c(TRUE, FALSE)) {
        dr <- if (across) 0L else 1L
        dc <- if (across) 1L else 0L
        if (starts_run(grid, row, column, dr, dc) && run_length(grid, row, column, dr, dc) == 2L) {
          return(paste("short slot at", location_text(grid, grid_cell(grid, row, column)), if (across) "across" else "down"))
        }
      }
    }
  }
  ""
}

new_layout <- function(grid) {
  numbers <- integer(length(grid$cells))
  across_slot <- down_slot <- integer(length(grid$cells))
  slots <- list()
  next_number <- 0L
  for (row in seq_len(grid$height) - 1L) {
    for (column in seq_len(grid$width) - 1L) {
      for (across in c(TRUE, FALSE)) {
        dr <- if (across) 0L else 1L
        dc <- if (across) 1L else 0L
        if (!starts_run(grid, row, column, dr, dc)) next
        size <- run_length(grid, row, column, dr, dc)
        if (size < 3L) next
        start <- grid_cell(grid, row, column)
        if (!numbers[start]) {
          next_number <- next_number + 1L
          numbers[start] <- next_number
        }
        number <- numbers[start]
        cells <- vapply(seq_len(size) - 1L, function(i) grid_cell(grid, row + i * dr, column + i * dc), integer(1))
        index <- length(slots) + 1L
        if (across) across_slot[cells] <- index else down_slot[cells] <- index
        slots[[index]] <- list(index = index, number = number, across = across, cells = cells, length = size, label = paste0(number, if (across) "A" else "D"), crossings = integer())
      }
    }
  }
  for (i in seq_along(slots)) {
    owners <- if (slots[[i]]$across) down_slot else across_slot
    crossing <- owners[slots[[i]]$cells]
    slots[[i]]$crossings <- sort(crossing[crossing > 0L], method = "radix")
  }
  list(grid = grid, numbers = numbers, slots = slots, across_slot = across_slot, down_slot = down_slot)
}

owner_count <- function(layout, cell) as.integer(layout$across_slot[cell] > 0L) + as.integer(layout$down_slot[cell] > 0L)
orphan_cell <- function(layout) {
  for (cell in white_cells(layout$grid)) if (!owner_count(layout, cell)) return(cell)
  0L
}
