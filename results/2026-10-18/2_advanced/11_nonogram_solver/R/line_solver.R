UNKNOWN <- 0L
FILLED <- 1L
EMPTY <- 2L
fit_table <- function(cells, clue) {
  n <- length(cells)
  m <- length(clue)
  empties <- c(0L, cumsum(cells == EMPTY))
  table <- matrix(FALSE, n + 1L, m + 1L)
  table[1L, 1L] <- TRUE
  for (end in seq_len(n)) for (count in 0:m) {
    fits <- cells[end] != FILLED && table[end, count + 1L]
    if (!fits && count > 0L) {
      start <- end - clue[count]
      if (start >= 0L && empties[end + 1L] == empties[start + 1L]) fits <- if (start == 0L) count == 1L else cells[start] != FILLED && table[start, count]
    }
    table[end + 1L, count + 1L] <- fits
  }
  table
}
has_placement <- function(cells, clue) fit_table(cells, clue)[length(cells) + 1L, length(clue) + 1L]
solve_line <- function(cells, clue, precise) {
  n <- length(cells)
  m <- length(clue)
  before <- fit_table(cells, clue)
  if (!before[n + 1L, m + 1L]) return(NULL)
  after <- fit_table(rev(cells), rev(clue))
  fillable <- covered <- rep(FALSE, n)
  solved <- cells
  for (block in seq_len(m)) {
    size <- clue[block]
    starts <- integer()
    for (start in 0:(n - size)) {
      end <- start + size
      if (any(cells[seq.int(start + 1L, end)] == EMPTY)) next
      left <- if (start == 0L) block == 1L else cells[start] != FILLED && before[start, block]
      right <- if (end == n) block == m else cells[end + 1L] != FILLED && after[n - end, m - block + 1L]
      if (left && right) starts <- c(starts, start)
    }
    if (precise) for (start in starts) fillable[seq.int(start + 1L, start + size)] <- TRUE
    else {
      low <- starts[1L]
      high <- tail(starts, 1L)
      if (high < low + size) {
        indices <- seq.int(high + 1L, low + size)
        solved[indices[cells[indices] == UNKNOWN]] <- FILLED
      }
      covered[seq.int(low + 1L, high + size)] <- TRUE
    }
  }
  for (index in which(cells == UNKNOWN)) {
    if (precise) {
      emptiable <- any(vapply(0:m, function(blocks) before[index, blocks + 1L] && after[n - index + 1L, m - blocks + 1L], logical(1L)))
      if (fillable[index] && !emptiable) solved[index] <- FILLED
      else if (!fillable[index] && emptiable) solved[index] <- EMPTY
    } else if (!covered[index]) solved[index] <- EMPTY
  }
  solved
}
