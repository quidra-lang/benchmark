neighborhood <- matrix(c(0, -1, 1, -1, 1, 0, 1, 1, 0, 1, -1, 1, -1, 0, -1, -1), ncol = 2L, byrow = TRUE)

occupied <- function(mask, x, y) {
  y >= 0 && y < nrow(mask) && x >= 0 && x < ncol(mask) && mask[y + 1L, x + 1L]
}

erode <- function(mask, offsets) {
  result <- matrix(FALSE, nrow(mask), ncol(mask))
  for (y in seq_len(nrow(mask)) - 1L) {
    for (x in seq_len(ncol(mask)) - 1L) {
      survives <- TRUE
      for (i in seq_len(nrow(offsets))) {
        if (!occupied(mask, x + offsets[i, 1L], y + offsets[i, 2L])) {
          survives <- FALSE
          break
        }
      }
      result[y + 1L, x + 1L] <- survives
    }
  }
  result
}

dilate <- function(mask, offsets) {
  result <- matrix(FALSE, nrow(mask), ncol(mask))
  for (y in seq_len(nrow(mask)) - 1L) {
    for (x in seq_len(ncol(mask)) - 1L) {
      for (i in seq_len(nrow(offsets))) {
        if (occupied(mask, x - offsets[i, 1L], y - offsets[i, 2L])) {
          result[y + 1L, x + 1L] <- TRUE
          break
        }
      }
    }
  }
  result
}

opening <- function(mask, offsets) dilate(erode(mask, offsets), offsets)
closing <- function(mask, offsets) erode(dilate(mask, offsets), offsets)

neighbor_bits <- function(mask, x, y) {
  vapply(seq_len(8L), function(i) occupied(mask, x + neighborhood[i, 1L], y + neighborhood[i, 2L]), logical(1))
}

transitions <- function(bits) sum(!bits & bits[c(2:8, 1L)])
crossing_number <- function(mask, x, y) transitions(neighbor_bits(mask, x, y))

removable <- function(bits, first_step) {
  count <- sum(bits)
  if (count < 2 || count > 6 || transitions(bits) != 1) return(FALSE)
  p2 <- bits[1L]
  p4 <- bits[3L]
  p6 <- bits[5L]
  p8 <- bits[7L]
  if (first_step) !(p2 && p4 && p6) && !(p4 && p6 && p8) else !(p2 && p4 && p8) && !(p2 && p6 && p8)
}

thinning_step <- function(mask, first_step) {
  removed <- matrix(FALSE, nrow(mask), ncol(mask))
  for (y in seq_len(nrow(mask)) - 1L) {
    for (x in seq_len(ncol(mask)) - 1L) {
      if (mask[y + 1L, x + 1L] && removable(neighbor_bits(mask, x, y), first_step)) {
        removed[y + 1L, x + 1L] <- TRUE
      }
    }
  }
  mask[removed] <- FALSE
  list(mask = mask, changed = any(removed))
}

thin <- function(mask) {
  repeat {
    first <- thinning_step(mask, TRUE)
    second <- thinning_step(first$mask, FALSE)
    mask <- second$mask
    if (!first$changed && !second$changed) return(mask)
  }
}
