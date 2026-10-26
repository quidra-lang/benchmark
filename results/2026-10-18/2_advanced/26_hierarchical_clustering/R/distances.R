distance_types <- c("euclidean", "manhattan", "correlation")
sequential_sum <- function(values) {
  total <- 0
  for (value in values) total <- total + value
  total
}
squared_distance <- function(u, w) {
  total <- 0
  for (f in seq_along(u)) {
    difference <- u[f] - w[f]
    total <- total + difference * difference
  }
  total
}
feature_statistics <- function(rows) {
  means <- deviations <- numeric(ncol(rows))
  for (f in seq_len(ncol(rows))) {
    mean <- sequential_sum(rows[, f]) / nrow(rows)
    squares <- 0
    for (value in rows[, f]) squares <- squares + (value - mean) * (value - mean)
    means[f] <- mean
    deviations[f] <- sqrt(squares / (nrow(rows) - 1))
  }
  list(means = means, deviations = deviations)
}
standardize_data <- function(rows, means, deviations) {
  result <- rows
  for (i in seq_len(nrow(rows))) for (f in seq_len(ncol(rows))) result[i, f] <- (rows[i, f] - means[f]) / deviations[f]
  result
}
distance <- function(u, w, kind) {
  if (kind == "euclidean") return(sqrt(squared_distance(u, w)))
  if (kind == "manhattan") return(sequential_sum(abs(u - w)))
  mu <- sequential_sum(u) / length(u)
  mw <- sequential_sum(w) / length(w)
  cross <- first <- second <- 0
  for (f in seq_along(u)) {
    du <- u[f] - mu
    dw <- w[f] - mw
    cross <- cross + du * dw
    first <- first + du * du
    second <- second + dw * dw
  }
  1 - cross / sqrt(first * second)
}
distance_matrix <- function(vectors, kind) {
  count <- nrow(vectors)
  matrix <- matrix(0, count, count)
  if (count > 1) for (i in seq_len(count - 1)) for (j in seq.int(i + 1, count)) {
    value <- distance(vectors[i, ], vectors[j, ], kind)
    matrix[i, j] <- matrix[j, i] <- value
  }
  matrix
}
