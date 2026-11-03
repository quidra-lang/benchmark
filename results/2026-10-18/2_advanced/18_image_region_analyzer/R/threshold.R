new_histogram <- function(image) {
  counts <- numeric(image$maxval + 1L)
  for (value in image$pixels) counts[value + 1L] <- counts[value + 1L] + 1
  below_counts <- cumsum(counts)
  below_sums <- cumsum((0:image$maxval) * counts)
  present <- which(counts > 0) - 1L
  pixels <- as.numeric(image$width * image$height)
  bin_width <- (image$maxval + 8L) %/% 8L
  bins <- vapply(seq.int(0L, image$maxval, by = bin_width), function(start) sum(counts[seq.int(start + 1L, min(start + bin_width, length(counts)))]), numeric(1))
  list(maxval = image$maxval, pixels = pixels, counts = counts, below_counts = below_counts, below_sums = below_sums, total = tail(below_sums, 1L), minimum = present[1L], maximum = tail(present, 1L), levels = length(present), median = which(2 * below_counts >= pixels)[1L] - 1L, mode = which.max(counts) - 1L, bin_width = bin_width, bins = bins)
}

split_histogram <- function(histogram, cutoff) {
  below <- histogram$below_counts[cutoff + 1L]
  sum_below <- histogram$below_sums[cutoff + 1L]
  c(below, sum_below, histogram$pixels - below, histogram$total - sum_below)
}

compare_scores <- function(first, second) {
  q1 <- first$numerator %/% first$denominator
  q2 <- second$numerator %/% second$denominator
  if (q1 != q2) return(sign(q1 - q2))
  left <- (first$numerator %% first$denominator) * second$denominator
  right <- (second$numerator %% second$denominator) * first$denominator
  sign(left - right)
}

otsu <- function(histogram) {
  ranked <- list()
  for (cutoff in seq_len(histogram$maxval) - 1L) {
    values <- split_histogram(histogram, cutoff)
    below <- values[1L]
    sum_below <- values[2L]
    above <- values[3L]
    sum_above <- values[4L]
    if (!histogram$counts[cutoff + 1L] || !above) next
    candidate <- list(cutoff = cutoff, below = below, sum_below = sum_below, above = above, sum_above = sum_above, numerator = sum_below * sum_below * above + sum_above * sum_above * below, denominator = below * above)
    position <- length(ranked) + 1L
    ranked[[position]] <- candidate
    while (position > 1L && compare_scores(candidate, ranked[[position - 1L]]) > 0) {
      ranked[[position]] <- ranked[[position - 1L]]
      position <- position - 1L
    }
    ranked[[position]] <- candidate
  }
  if (!length(ranked)) return(list(cutoff = histogram$minimum, upper = histogram$minimum, candidates = ranked))
  cutoff <- ranked[[1L]]$cutoff
  following <- cutoff + 1L
  while (histogram$counts[following + 1L] == 0) following <- following + 1L
  list(cutoff = cutoff, upper = following - 1L, candidates = ranked)
}

isodata <- function(histogram) {
  cutoff <- histogram$total %/% histogram$pixels
  iterations <- 0L
  repeat {
    values <- split_histogram(histogram, cutoff)
    below <- values[1L]
    sum_below <- values[2L]
    above <- values[3L]
    sum_above <- values[4L]
    if (!below || !above) break
    following <- (sum_below * above + sum_above * below) %/% (2 * below * above)
    iterations <- iterations + 1L
    if (following == cutoff) break
    cutoff <- following
    if (iterations == 100L) break
  }
  c(cutoff, iterations)
}
