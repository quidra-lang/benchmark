lance_williams <- function(method, na, nb, nk) {
  switch(method, single = c(0.5, 0.5, 0, -0.5), complete = c(0.5, 0.5, 0, 0.5),
         average = c(na / (na + nb), nb / (na + nb), 0, 0), weighted = c(0.5, 0.5, 0, 0),
         centroid = c(na / (na + nb), nb / (na + nb), -(na * nb) / ((na + nb) * (na + nb)), 0),
         median = c(0.5, 0.5, -0.25, 0), ward = c((na + nk) / (na + nb + nk), (nb + nk) / (na + nb + nk), -nk / (na + nb + nk), 0))
}
agglomerate <- function(delta, method) {
  count <- nrow(delta)
  squared <- method %in% c("centroid", "median", "ward")
  capacity <- 2 * count - 1
  values <- matrix(0, capacity, capacity)
  values[seq_len(count), seq_len(count)] <- if (squared) delta * delta else delta
  sizes <- c(rep(1, count), rep(0, count - 1))
  active <- seq_len(count)
  merges <- list()
  for (step in seq_len(count - 1)) {
    a <- active[1]
    b <- active[2]
    best <- values[a, b]
    for (position in seq_len(length(active) - 1)) for (next_position in seq.int(position + 1, length(active))) {
      u <- active[position]
      w <- active[next_position]
      if (values[u, w] < best) {
        a <- u
        b <- w
        best <- values[u, w]
      }
    }
    node <- count + step
    sizes[node] <- sizes[a] + sizes[b]
    merges[[step]] <- list(a = a, b = b, height = if (squared) sqrt(best) else best, size = sizes[node])
    for (k in active) {
      if (k == a || k == b) next
      coefficients <- lance_williams(method, sizes[a], sizes[b], sizes[k])
      value <- coefficients[1] * values[a, k] + coefficients[2] * values[b, k] + coefficients[3] * values[a, b] + coefficients[4] * abs(values[a, k] - values[b, k])
      values[node, k] <- values[k, node] <- value
    }
    active <- c(active[active != a & active != b], node)
  }
  merges
}
minimum_spanning_tree <- function(delta) {
  count <- nrow(delta)
  in_tree <- rep(FALSE, count)
  in_tree[1] <- TRUE
  key <- delta[1, ]
  parent <- rep(1L, count)
  edges <- list()
  for (step in seq_len(count - 1)) {
    chosen <- 0L
    for (u in seq_len(count)) if (!in_tree[u] && (!chosen || key[u] < key[chosen])) chosen <- u
    in_tree[chosen] <- TRUE
    edges[[step]] <- list(parent = parent[chosen], child = chosen, weight = key[chosen])
    for (u in seq_len(count)) if (!in_tree[u] && delta[chosen, u] < key[u]) {
      key[u] <- delta[chosen, u]
      parent[u] <- chosen
    }
  }
  edges
}
