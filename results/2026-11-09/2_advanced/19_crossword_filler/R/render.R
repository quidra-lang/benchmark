decimal_text <- function(numerator, denominator, places) {
  scale <- 10^places
  rounded <- (2 * numerator * scale + denominator) %/% (2 * denominator)
  fraction <- sprintf("%.0f", rounded %% scale)
  paste0(sprintf("%.0f", rounded %/% scale), ".", strrep("0", places - nchar(fraction)), fraction)
}

grid_lines <- function(grid, letters) {
  vapply(seq_len(grid$height), function(row) paste(letters[seq.int((row - 1L) * grid$width + 1L, row * grid$width)], collapse = ""), character(1))
}

number_lines <- function(layout) {
  grid <- layout$grid
  vapply(seq_len(grid$height) - 1L, function(row) {
    marks <- vapply(seq_len(grid$width) - 1L, function(column) {
      cell <- grid_cell(grid, row, column)
      if (grid$cells[cell] == "#") "##" else if (layout$numbers[cell]) sprintf("%2d", layout$numbers[cell]) else " ."
    }, character(1))
    paste(marks, collapse = " ")
  }, character(1))
}

list_line <- function(slot, clue, entry, score, theme) {
  paste0(slot$number, ". ", clue, " (", slot$length, ") ", entry, " ", score, if (theme) " theme" else "")
}
