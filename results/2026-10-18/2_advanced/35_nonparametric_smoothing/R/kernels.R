KAPPA <- c(epanechnikov = 0.75, biweight = 0.9375, triweight = 1.09375)
new_model <- function(...) list2env(list(...), parent = emptyenv())
kernel_fit <- function(positions, values, bandwidth, kernel, local_linear, diagnostics = TRUE) {
  model <- new_model(positions = positions, x = positions / 100, y = values, bandwidth = bandwidth,
                     kernel = kernel, local_linear = local_linear, fitted = NULL, leverage = NULL, edf = NULL,
                     cache = new.env(hash = TRUE, parent = emptyenv()))
  model$evaluate <- function(position) {
    key <- as.character(position)
    if (exists(key, envir = model$cache, inherits = FALSE)) return(model$cache[[key]])
    used <- which(abs(positions - position) < bandwidth)
    if (length(used) < (if (local_linear) 2L else 1L)) {
      result <- list(value = NULL, weights = NULL)
      model$cache[[key]] <- result
      return(result)
    }
    x0 <- position / 100
    h <- bandwidth / 100
    differences <- kernels <- numeric()
    for (i in used) {
      delta <- model$x[[i]] - x0
      u <- delta / h
      t <- 1 - u * u
      weight <- KAPPA[[kernel]] * t
      if (kernel != "epanechnikov") weight <- weight * t
      if (kernel == "triweight") weight <- weight * t
      differences <- c(differences, delta)
      kernels <- c(kernels, weight)
    }
    s0 <- ordered_sum(kernels)
    t0 <- ordered_sum(kernels * values[used])
    weights <- numeric(length(positions))
    if (local_linear) {
      s1 <- ordered_sum(kernels * differences)
      s2 <- ordered_sum(kernels * differences * differences)
      t1 <- ordered_sum(kernels * differences * values[used])
      determinant <- s0 * s2 - s1 * s1
      value <- (s2 * t0 - s1 * t1) / determinant
      weights[used] <- kernels * (s2 - s1 * differences) / determinant
    } else {
      value <- t0 / s0
      weights[used] <- kernels / s0
    }
    result <- list(value = value, weights = weights)
    model$cache[[key]] <- result
    result
  }
  model$estimate <- function(position) model$evaluate(position)$value
  model$weights <- function(position) model$evaluate(position)$weights
  if (diagnostics) {
    pairs <- lapply(positions, model$evaluate)
    if (!any(vapply(pairs, function(pair) is.null(pair$value), FALSE))) {
      model$fitted <- vapply(pairs, `[[`, 0, "value")
      model$leverage <- vapply(seq_along(pairs), function(i) pairs[[i]]$weights[[i]], 0)
      model$edf <- ordered_sum(model$leverage)
    }
  }
  model
}
