distance_table <- function(points) {
  count <- length(points)
  table <- matrix(0, count, count)
  for (first in seq_len(count - 1L)) {
    for (second in seq.int(first + 1L, count)) {
      distance <- sqrt(squared_distance(points[[first]], points[[second]]))
      table[first, second] <- distance
      table[second, first] <- distance
    }
  }
  table
}

silhouettes <- function(table, labels, sizes) {
  values <- numeric(length(labels))
  for (index in seq_along(labels)) {
    own <- labels[index]
    if (sizes[own] == 1L) next
    totals <- numeric(length(sizes))
    for (other in seq_along(labels)) {
      if (other != index) totals[labels[other]] <- totals[labels[other]] + table[index, other]
    }
    inner <- totals[own] / (sizes[own] - 1L)
    outer <- min((totals / sizes)[-own])
    largest <- max(inner, outer)
    if (largest != 0) values[index] <- (outer - inner) / largest
  }
  values
}

calinski_harabasz <- function(points, centers, sizes, within) {
  overall <- mean_point(points)
  between <- 0
  for (index in seq_along(centers)) between <- between + sizes[index] * squared_distance(centers[[index]], overall)
  (between / (length(centers) - 1L)) / (within / (length(points) - length(centers)))
}

davies_bouldin <- function(points, labels, centers, sizes) {
  spreads <- numeric(length(centers))
  for (index in seq_along(points)) spreads[labels[index]] <- spreads[labels[index]] + sqrt(squared_distance(points[[index]], centers[[labels[index]]]))
  spreads <- spreads / sizes
  total <- 0
  for (first in seq_along(centers)) {
    worst <- 0
    for (second in seq_along(centers)) {
      if (first == second) next
      value <- (spreads[first] + spreads[second]) / sqrt(squared_distance(centers[[first]], centers[[second]]))
      worst <- max(worst, value)
    }
    total <- total + worst
  }
  total / length(centers)
}

elbow <- function(k, first, last, within, within_first, within_last) {
  x <- (k - first) / (last - first)
  y <- (within - within_last) / (within_first - within_last)
  ((1 - x) - y) / sqrt(2)
}
hartigan <- function(within, next_within, count, k) (within / next_within - 1) * (count - k - 1)
pair_count <- function(size) {
  size <- as.numeric(size)
  size * (size - 1) / 2
}

adjusted_rand <- function(first, second) {
  left <- match(first, unique(first))
  right <- match(second, unique(second))
  joint <- matrix(0, max(left), max(right))
  for (index in seq_along(left)) joint[left[index], right[index]] <- joint[left[index], right[index]] + 1
  z <- pair_count(length(first))
  shared <- sum(pair_count(joint))
  sx <- sum(pair_count(rowSums(joint)))
  sy <- sum(pair_count(colSums(joint)))
  numerator <- 2 * (z * shared - sx * sy)
  denominator <- z * (sx + sy) - 2 * sx * sy
  if (denominator == 0) 1 else numerator / denominator
}
