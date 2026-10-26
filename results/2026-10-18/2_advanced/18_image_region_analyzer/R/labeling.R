label_components <- function(mask, connectivity) {
  height <- nrow(mask)
  width <- ncol(mask)
  previous <- if (connectivity == 4L) matrix(c(-1L, 0L, 0L, -1L), ncol = 2L, byrow = TRUE) else matrix(c(-1L, 0L, -1L, -1L, 0L, -1L, 1L, -1L), ncol = 2L, byrow = TRUE)
  provisional <- matrix(0L, height, width)
  parents <- 0L
  find_root <- function(label) {
    while (parents[label + 1L] != label) {
      parents[label + 1L] <<- parents[parents[label + 1L] + 1L]
      label <- parents[label + 1L]
    }
    label
  }
  union_roots <- function(first, second) {
    a <- find_root(first)
    b <- find_root(second)
    if (a != b) parents[max(a, b) + 1L] <<- min(a, b)
  }
  for (y in seq_len(height) - 1L) {
    for (x in seq_len(width) - 1L) {
      if (!mask[y + 1L, x + 1L]) next
      neighbors <- integer()
      for (i in seq_len(nrow(previous))) {
        nx <- x + previous[i, 1L]
        ny <- y + previous[i, 2L]
        if (occupied(mask, nx, ny)) neighbors <- c(neighbors, provisional[ny + 1L, nx + 1L])
      }
      if (!length(neighbors)) {
        provisional[y + 1L, x + 1L] <- length(parents)
        parents <- c(parents, length(parents))
      } else {
        provisional[y + 1L, x + 1L] <- neighbors[1L]
        for (other in neighbors[-1L]) union_roots(neighbors[1L], other)
      }
    }
  }
  numbers <- integer(length(parents))
  labels <- matrix(0L, height, width)
  count <- 0L
  for (y in seq_len(height)) {
    for (x in seq_len(width)) {
      if (!provisional[y, x]) next
      root <- find_root(provisional[y, x])
      if (!numbers[root + 1L]) {
        count <- count + 1L
        numbers[root + 1L] <- count
      }
      labels[y, x] <- numbers[root + 1L]
    }
  }
  list(labels = labels, count = count, provisional = length(parents) - 1L)
}

bit_quad_euler <- function(mask, connectivity) {
  singles <- triples <- diagonals <- 0L
  for (y in seq.int(-1L, nrow(mask) - 1L)) {
    for (x in seq.int(-1L, ncol(mask) - 1L)) {
      tl <- occupied(mask, x, y)
      tr <- occupied(mask, x + 1L, y)
      bl <- occupied(mask, x, y + 1L)
      br <- occupied(mask, x + 1L, y + 1L)
      count <- sum(c(tl, tr, bl, br))
      if (count == 1L) singles <- singles + 1L else if (count == 3L) triples <- triples + 1L else if (count == 2L && ((tl && br) || (tr && bl))) diagonals <- diagonals + 1L
    }
  }
  (singles - triples + (if (connectivity == 8L) -2L else 2L) * diagonals) %/% 4L
}
