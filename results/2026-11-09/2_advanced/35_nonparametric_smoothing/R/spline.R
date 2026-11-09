spline_fit <- function(positions, values, penalty, diagnostics = TRUE) {
  x <- positions / 100
  h <- diff(x)
  size <- length(positions) - 2L
  a <- 1 / h[seq_len(size)]
  c <- 1 / h[seq.int(2L, size + 1L)]
  b <- -(a + c)
  diagonal <- vapply(
      seq_len(size),
      function(i) (h[[i]] + h[[i + 1L]]) / 3 + penalty * (a[[i]] * a[[i]] + b[[i]] * b[[i]] + c[[i]] * c[[i]]),
      0
  )
  first_band <- vapply(
      seq_len(size - 1L),
      function(i) h[[i + 1L]] / 6 + penalty * c[[i]] * (b[[i]] + b[[i + 1L]]),
      0
  )
  second_band <- vapply(seq_len(size - 2L), function(i) penalty * c[[i]] * c[[i + 1L]], 0)
  d <- l1 <- l2 <- numeric(size)
  for (i in seq_len(size)) {
    if (i >= 3L) l2[[i]] <- second_band[[i - 2L]] / d[[i - 2L]]
    if (i >= 2L) {
      correction <- if (i >= 3L) l2[[i]] * d[[i - 2L]] * l1[[i - 1L]] else 0
      l1[[i]] <- (first_band[[i - 1L]] - correction) / d[[i - 1L]]
    }
    value <- diagonal[[i]]
    if (i >= 2L) value <- value - l1[[i]] * l1[[i]] * d[[i - 1L]]
    if (i >= 3L) value <- value - l2[[i]] * l2[[i]] * d[[i - 2L]]
    d[[i]] <- value
  }
  model <- new_model(positions = positions, x = x, h = h, penalty = penalty, d = d, l1 = l1, l2 = l2,
                     fit = NULL, fitted = NULL, basis = NULL, leverage = NULL, edf = NULL)
  model$fit_values <- function(values) {
    n <- length(values)
    z <- numeric(size)
    for (i in seq_len(size)) {
      value <- (values[[i + 2L]] - values[[i + 1L]]) / h[[i + 1L]] - (values[[i + 1L]] - values[[i]]) / h[[i]]
      if (i >= 2L) value <- value - l1[[i]] * z[[i - 1L]]
      if (i >= 3L) value <- value - l2[[i]] * z[[i - 2L]]
      z[[i]] <- value
    }
    gamma <- numeric(n)
    for (i in rev(seq_len(size))) {
      value <- z[[i]] / d[[i]]
      if (i + 1L <= size) value <- value - l1[[i + 1L]] * gamma[[i + 2L]]
      if (i + 2L <= size) value <- value - l2[[i + 2L]] * gamma[[i + 3L]]
      gamma[[i + 1L]] <- value
    }
    omega <- numeric(n)
    omega[[1L]] <- (gamma[[2L]] - gamma[[1L]]) / h[[1L]]
    for (i in seq.int(
        2L,
        n - 1L
    )) omega[[i]] <- (gamma[[i + 1L]] - gamma[[i]]) / h[[i]] - (gamma[[i]] - gamma[[i - 1L]]) / h[[i - 1L]]
    omega[[n]] <- 0 - (gamma[[n]] - gamma[[n - 1L]]) / h[[n - 1L]]
    list(fitted = values - penalty * omega, gamma = gamma)
  }
  model$evaluate_fit <- function(fit, position) {
    fitted <- fit$fitted
    gamma <- fit$gamma
    x0 <- position / 100
    n <- length(positions)
    index <- which(positions >= position)[1L]
    if (!is.na(index) && positions[[index]] == position) return(fitted[[index]])
    if (!is.na(index) && index == 1L) {
      slope <- (fitted[[2L]] - fitted[[1L]]) / h[[1L]] - h[[1L]] * gamma[[2L]] / 6
      return(fitted[[1L]] - (x[[1L]] - x0) * slope)
    }
    if (is.na(index)) {
      slope <- (fitted[[n]] - fitted[[n - 1L]]) / h[[n - 1L]] + h[[n - 1L]] * gamma[[n - 1L]] / 6
      return(fitted[[n]] + (x0 - x[[n]]) * slope)
    }
    i <- index - 1L
    left <- x0 - x[[i]]
    right <- x[[i + 1L]] - x0
    (left * fitted[[i + 1L]] + right * fitted[[i]]) / h[[i]] - left * right * ((1 + left / h[[i]]) * gamma[[i + 1L]] + (1 + right / h[[i]]) * gamma[[i]]) / 6
  }
  model$prepare_basis <- function() {
    if (!is.null(model$basis)) return(invisible(NULL))
    n <- length(positions)
    model$basis <- lapply(seq_len(n), function(i) {
      unit <- numeric(n)
      unit[[i]] <- 1
      model$fit_values(unit)
    })
    model$leverage <- vapply(seq_len(n), function(i) model$basis[[i]]$fitted[[i]], 0)
    model$edf <- ordered_sum(model$leverage)
  }
  model$fit <- model$fit_values(values)
  model$fitted <- model$fit$fitted
  model$estimate <- function(position) model$evaluate_fit(model$fit, position)
  model$weights <- function(position) {
    model$prepare_basis()
    vapply(model$basis, function(fit) model$evaluate_fit(fit, position), 0)
  }
  if (diagnostics) model$prepare_basis()
  model
}
