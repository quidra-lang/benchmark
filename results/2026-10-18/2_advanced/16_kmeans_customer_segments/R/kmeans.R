squared_distance <- function(first, second) {
  total <- 0
  for (index in seq_along(first)) {
    difference <- first[index] - second[index]
    total <- total + difference * difference
  }
  total
}

assign_points <- function(points, centers) {
  labels <- integer(length(points))
  errors <- numeric(length(points))
  for (index in seq_along(points)) {
    distances <- vapply(centers, function(center) squared_distance(points[[index]], center), numeric(1L))
    best <- which.min(distances)
    labels[index] <- best
    errors[index] <- distances[best]
  }
  list(labels = labels, errors = errors)
}

mean_point <- function(points) {
  totals <- numeric(length(points[[1L]]))
  for (point in points) {
    for (feature in seq_along(point)) totals[feature] <- totals[feature] + point[feature]
  }
  totals / length(points)
}
cluster_sizes <- function(labels, k) tabulate(labels, nbins = k)
cluster_center <- function(points, labels, cluster) mean_point(points[labels == cluster])
cluster_centers <- function(points, labels, k) lapply(seq_len(k), function(cluster) cluster_center(points, labels, cluster))

refill <- function(labels, errors, k) {
  sizes <- cluster_sizes(labels, k)
  reseeds <- 0L
  for (cluster in seq_len(k)) {
    if (sizes[cluster] > 0L) next
    eligible <- which(sizes[labels] >= 2L)
    chosen <- eligible[which.max(errors[eligible])]
    sizes[labels[chosen]] <- sizes[labels[chosen]] - 1L
    sizes[cluster] <- sizes[cluster] + 1L
    labels[chosen] <- cluster
    errors[chosen] <- 0
    reseeds <- reseeds + 1L
  }
  list(labels = labels, errors = errors, reseeds = reseeds)
}

lloyd <- function(points, initial, limit) {
  k <- length(initial)
  current <- assign_points(points, initial)
  iterations <- reseeds <- 0L
  converged <- FALSE
  while (iterations < limit && !converged) {
    current <- refill(current$labels, current$errors, k)
    reseeds <- reseeds + current$reseeds
    centers <- cluster_centers(points, current$labels, k)
    iterations <- iterations + 1L
    updated <- assign_points(points, centers)
    converged <- identical(updated$labels, current$labels)
    current <- updated
  }
  current <- refill(current$labels, current$errors, k)
  reseeds <- reseeds + current$reseeds
  list(labels = current$labels, centers = cluster_centers(points, current$labels, k),
       iterations = iterations, converged = converged, reseeds = reseeds)
}

sse <- function(points, labels, centers) {
  ordered_sum(vapply(seq_along(points), function(index) squared_distance(points[[index]], centers[[labels[index]]]), numeric(1L)))
}
