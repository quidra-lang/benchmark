median_value <- function(values) {
  ordered <- sort(values)
  middle <- length(ordered) %/% 2L
  if (length(ordered) %% 2L) ordered[[middle + 1L]] else (ordered[[middle]] + ordered[[middle + 1L]]) / 2
}
cholesky_lower <- function(matrix) {
  n <- nrow(matrix)
  lower <- matrix(0, n, n)
  for (row in seq_len(n)) {
    for (column in seq_len(row)) {
      sigma <- matrix[row, column]
      for (k in seq_len(column - 1L)) sigma <- sigma - lower[row, k] * lower[column, k]
      lower[row, column] <- if (row == column) sqrt(sigma) else sigma / lower[column, column]
    }
  }
  lower
}
solve_lower <- function(lower, right) {
  n <- length(right)
  intermediate <- solution <- numeric(n)
  for (row in seq_len(n)) {
    value <- right[[row]]
    for (k in seq_len(row - 1L)) value <- value - lower[row, k] * intermediate[[k]]
    intermediate[[row]] <- value / lower[row, row]
  }
  for (row in rev(seq_len(n))) {
    value <- intermediate[[row]]
    if (row < n) for (k in seq.int(row + 1L, n)) value <- value - lower[k, row] * solution[[k]]
    solution[[row]] <- value / lower[row, row]
  }
  solution
}
loess_fit <- function(positions, values, span, degree, iterations, diagnostics = TRUE) {
  model <- new_model(positions = positions, x = positions / 100, y = values, span = span, degree = degree,
                     rho = rep.int(1, length(positions)), records = list(), cache = new.env(
                         hash = TRUE,
                         parent = emptyenv()
                     ),
                     fitted = NULL, leverage = NULL, edf = NULL)
  model$local_fit <- function(position) {
    n <- length(positions)
    q <- (span * n) %/% 100L
    neighborhood <- order(abs(positions - position), seq_len(n), method = "radix")[seq_len(q)]
    distance <- max(abs(positions[neighborhood] - position))
    size <- degree + 1L
    matrix <- matrix(0, size, size)
    right <- numeric(size)
    rows <- list()
    for (i in sort(neighborhood)) {
      a <- abs(positions[[i]] - position) / distance
      s <- 1 - a * a * a
      weight <- s * s * s * model$rho[[i]]
      delta <- model$x[[i]] - position / 100
      basis <- if (degree == 1L) c(1, delta) else c(1, delta, delta * delta)
      rows[[length(rows) + 1L]] <- list(index = i, weight = weight, basis = basis)
      for (row in seq_len(size)) {
        right[[row]] <- right[[row]] + weight * basis[[row]] * values[[i]]
        for (column in seq_len(size)) matrix[row, column] <- matrix[
            row,
            column
        ] + weight * basis[[row]] * basis[[column]]
      }
    }
    lower <- cholesky_lower(matrix)
    beta <- solve_lower(lower, right)
    zeta <- solve_lower(lower, c(1, numeric(degree)))
    weights <- numeric(n)
    for (row in rows) weights[[row$index]] <- row$weight * ordered_sum(zeta * row$basis)
    list(value = beta[[1L]], zeta = zeta[[1L]], weights = weights)
  }
  model$evaluate <- function(position) {
    key <- as.character(position)
    if (!exists(key, envir = model$cache, inherits = FALSE)) model$cache[[key]] <- model$local_fit(position)
    model$cache[[key]]
  }
  model$estimate <- function(position) model$evaluate(position)$value
  model$weights <- function(position) model$evaluate(position)$weights
  if (diagnostics) {
    fits <- lapply(positions, model$local_fit)
    for (iteration in seq_len(iterations)) {
      residuals <- values - vapply(fits, `[[`, 0, "value")
      scale <- median_value(abs(residuals))
      for (i in seq_along(residuals)) {
        u <- residuals[[i]] / (6 * scale)
        v <- 1 - u * u
        model$rho[[i]] <- if (abs(u) < 1) v * v else 0
      }
      updated <- lapply(positions, model$local_fit)
      change <- max(abs(vapply(updated, `[[`, 0, "value") - vapply(fits, `[[`, 0, "value")))
      model$records[[length(model$records) + 1L]] <- list(
          iteration = iteration,
          scale = scale,
          zero_count = sum(model$rho == 0),
          change = change
      )
      fits <- updated
    }
    for (i in seq_along(positions)) model$cache[[as.character(positions[[i]])]] <- fits[[i]]
    model$fitted <- vapply(fits, `[[`, 0, "value")
    model$leverage <- model$rho * vapply(fits, `[[`, 0, "zeta")
    model$edf <- ordered_sum(model$leverage)
  }
  model
}
