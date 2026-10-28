samples_per_tick <- function(rate, tempo) (rate * 5) %/% (tempo * 2)
next_row <- function(song, position, row) {
  jump <- pattern_break <- NULL
  for (cell in song_cells(song, position, row)) {
    effect <- cell$effect
    if (is.null(effect)) next
    if (effect$name == "F" && effect$value == 0L) return(NULL)
    if (effect$name == "B") jump <- effect$value else if (effect$name == "D") pattern_break <- effect$value
  }
  if (is.null(jump) && is.null(pattern_break)) return(if (row < ROWS_PER_PATTERN - 1L) c(
      position,
      row + 1L
  ) else c(position + 1L, 0L))
  c(
      if (is.null(jump)) position + 1L else jump,
      if (is.null(pattern_break) || pattern_break >= ROWS_PER_PATTERN) 0L else pattern_break
  )
}
row_key <- function(position, row) paste(position, row, sep = ":")
reachable_rows <- function(song) {
  reached <- character()
  current <- c(0L, 0L)
  while (!is.null(current) && !(row_key(current[[1L]], current[[2L]]) %in% reached)) {
    reached <- c(reached, row_key(current[[1L]], current[[2L]]))
    current <- next_row(song, current[[1L]], current[[2L]])
    if (!is.null(current) && current[[1L]] >= length(song$order)) current <- NULL
  }
  reached
}
