distance <- function(a, b, metric) {
  if (metric == "squared_euclidean") return(real_sum((a - b) * (a - b)))
  if (metric == "manhattan") return(real_sum(abs(a - b)))
  if (metric == "chebyshev") return(max(abs(a - b)))
  dot <- real_sum(a * b)
  na <- sqrt(real_sum(a * a))
  nb <- sqrt(real_sum(b * b))
  if (na == 0 || nb == 0) 1 else 1 - dot / (na * nb)
}

sort_neighbors <- function(neighbors) neighbors[order(vapply(neighbors, function(neighbor) neighbor$distance, numeric(1L)), vapply(neighbors, function(neighbor) neighbor$row$id, character(1L)), method = "radix")]

neighbor_order <- function(query, references, metric) sort_neighbors(lapply(references, function(reference) list(distance = distance(query, reference$values, metric), row = reference$row)))

vote <- function(nearest, weighting) {
  labels <- sort(unique(vapply(nearest, function(neighbor) neighbor$row$label, character(1L))), method = "radix")
  counts <- distance_sums <- weight_sums <- setNames(rep(0, length(labels)), labels)
  total <- 0
  for (neighbor in nearest) {
    label <- neighbor$row$label
    weight <- 1 / (neighbor$distance + 0.000000001)
    counts[label] <- counts[label] + 1L
    distance_sums[label] <- distance_sums[label] + neighbor$distance
    weight_sums[label] <- weight_sums[label] + weight
    total <- total + weight
  }
  priority <- if (weighting == "uniform") counts else weight_sums
  ranked <- labels[order(-priority, distance_sums, labels, method = "radix")]
  shares <- if (weighting == "uniform") counts[ranked] / length(nearest) else weight_sums[ranked] / total
  list(label = ranked[1L], share = unname(shares[1L]), runner_up = if (length(ranked) > 1L) ranked[2L] else "-", runner_share = if (length(ranked) > 1L) unname(shares[2L]) else 0)
}

estimate <- function(nearest, weighting) {
  if (weighting == "uniform") return(real_sum(vapply(nearest, function(neighbor) neighbor$row$target, numeric(1L))) / length(nearest))
  weighted <- weights <- 0
  for (neighbor in nearest) {
    weight <- 1 / (neighbor$distance + 0.000000001)
    weighted <- weighted + weight * neighbor$row$target
    weights <- weights + weight
  }
  weighted / weights
}
