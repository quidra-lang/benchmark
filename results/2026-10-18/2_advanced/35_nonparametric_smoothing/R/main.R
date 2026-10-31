for (name in c("dataset", "selection", "kernels", "loess", "spline")) source(paste0(name, ".R"))

estimate <- function(model, position) model$estimate(position)
weights <- function(model, position) model$weights(position)
residual_square <- function(observed, fitted) ordered_sum((observed - fitted) * (observed - fitted))
linear_fit <- function(points) {
  x <- points[, 1L] / 100
  y <- points[, 2L] / 100
  n <- nrow(points)
  xbar <- ordered_sum(x) / n
  ybar <- ordered_sum(y) / n
  sxx <- ordered_sum((x - xbar) * (x - xbar))
  sxy <- ordered_sum((x - xbar) * (y - ybar))
  slope <- sxy / sxx
  intercept <- ybar - slope * xbar
  new_model(fitted = intercept + slope * x, leverage = 1 / n + (x - xbar) * (x - xbar) / sxx, edf = 2,
            estimate = function(position) intercept + slope * (position / 100),
            weights = function(position) 1 / n + (position / 100 - xbar) * (x - xbar) / sxx)
}
running_fit <- function(points, width, use_median) {
  positions <- points[, 1L]
  n <- nrow(points)
  half <- (width - 1L) %/% 2L
  windows <- vector("list", n)
  fitted <- diagonal <- numeric(n)
  for (i in seq_len(n)) {
    radius <- min(half, i - 1L, n - i)
    window <- seq.int(i - radius, i + radius)
    values <- points[window, 2L]
    windows[[i]] <- window
    fitted[[i]] <- if (use_median) sort(values)[[radius + 1L]] / 100 else sum(values) / (100 * length(values))
    diagonal[[i]] <- 1 / length(values)
  }
  nearest <- function(position) which.min(abs(positions - position))
  new_model(fitted = fitted, leverage = if (use_median) NULL else diagonal, edf = if (use_median) NULL else ordered_sum(diagonal),
            estimate = function(position) fitted[[nearest(position)]],
            weights = function(position) {
              window <- windows[[nearest(position)]]
              result <- numeric(n)
              result[window] <- 1 / length(window)
              result
            })
}
fit_direction <- function(points, direction) {
  blocks <- list()
  for (i in seq_len(nrow(points))) {
    blocks[[length(blocks) + 1L]] <- c(i, i, points[i, 2L], 1L)
    while (length(blocks) >= 2L) {
      left <- blocks[[length(blocks) - 1L]]
      right <- blocks[[length(blocks)]]
      a <- left[[3L]] * right[[4L]]
      b <- right[[3L]] * left[[4L]]
      violates <- if (direction == "increasing") a > b else a < b
      if (!violates) break
      blocks <- head(blocks, -2L)
      blocks[[length(blocks) + 1L]] <- c(
          left[[1L]],
          right[[2L]],
          left[[3L]] + right[[3L]],
          left[[4L]] + right[[4L]]
      )
    }
  }
  fitted <- numeric(nrow(points))
  for (block in blocks) fitted[seq.int(block[[1L]], block[[2L]])] <- block[[3L]] / (100 * block[[4L]])
  list(fitted = fitted, blocks = blocks)
}
isotonic_fit <- function(points, mode) {
  positions <- points[, 1L]
  observed <- points[, 2L] / 100
  increasing <- fit_direction(points, "increasing")
  decreasing <- fit_direction(points, "decreasing")
  rss_increasing <- residual_square(observed, increasing$fitted)
  rss_decreasing <- residual_square(observed, decreasing$fitted)
  direction <- if (mode == "auto") if (rss_increasing <= rss_decreasing) "increasing" else "decreasing" else mode
  fit <- if (direction == "increasing") increasing else decreasing
  fitted <- fit$fitted
  new_model(positions = positions, mode = mode, direction = direction, fitted = fitted, blocks = fit$blocks,
            leverage = NULL, edf = as.numeric(length(fit$blocks)), rss_increasing = rss_increasing, rss_decreasing = rss_decreasing,
            estimate = function(position) {
              index <- which(positions <= position)
              fitted[[if (length(index)) tail(index, 1L) else 1L]]
            })
}
methods_in_order <- function(settings) c("linear", "running_mean", "running_median", paste0("nw_", settings$KERNELS),
                                        paste0("ll_", settings$KERNELS), paste0(
                                            "loess",
                                            settings$LOESS_DEGREES
                                        ), "spline", "isotonic")
parameters_for <- function(method, settings) {
  if (startsWith(method, "running_")) return(settings$WINDOWS)
  if (startsWith(method, "nw_") || startsWith(method, "ll_")) return(settings$BANDWIDTHS)
  if (startsWith(method, "loess")) return(settings$SPANS)
  if (method == "spline") settings$LAMBDAS else character()
}
fit_model <- function(method, parameter, points, settings, direction, robust = TRUE, diagnostics = TRUE) {
  if (method == "linear") return(linear_fit(points))
  if (startsWith(method, "running_")) return(running_fit(
      points,
      as.integer(parameter),
      method == "running_median"
  ))
  if (method == "isotonic") return(isotonic_fit(points, direction))
  positions <- points[, 1L]
  values <- points[, 2L] / 100
  if (startsWith(method, "nw_") || startsWith(method, "ll_")) {
    return(kernel_fit(
        positions,
        values,
        hundredths(parameter),
        substring(method, 4L),
        startsWith(method, "ll_"),
        diagnostics
    ))
  }
  if (startsWith(method, "loess")) {
    iterations <- if (robust) settings$ROBUST_ITERATIONS else 0L
    return(loess_fit(
        positions,
        values,
        hundredths(parameter),
        as.integer(substring(method, 6L)),
        iterations,
        diagnostics
    ))
  }
  spline_fit(positions, values, as.numeric(parameter), diagnostics)
}
validation_predictions <- function(method, parameter, points, settings, direction, folds) {
  predictions <- vector("list", nrow(points))
  indices <- seq_len(nrow(points))
  for (group in seq_len(folds)) {
    held <- which((indices - 1L) %% folds == group - 1L)
    model <- fit_model(
        method,
        parameter,
        points[-held, , drop = FALSE],
        settings,
        direction,
        robust = FALSE,
        diagnostics = FALSE
    )
    for (i in held) predictions[i] <- list(estimate(model, points[i, 1L]))
  }
  predictions
}
select_models <- function(points, settings, methods, mode) {
  observed <- points[, 2L] / 100
  entries <- list()
  for (method in methods) {
    candidates <- list()
    for (parameter in parameters_for(method, settings)) {
      candidate <- fit_model(method, parameter, points, settings, mode, robust = FALSE)
      score <- if (method == "spline") generalized_score(observed, candidate$fitted, candidate$edf) else cross_validation_score(
          observed,
          validation_predictions(method, parameter, points, settings, mode, nrow(points))
      )
      candidates[[length(candidates) + 1L]] <- list(parameter = parameter, score = score, edf = candidate$edf)
    }
    best <- if (length(candidates)) choose_candidate(candidates) else 0L
    parameter <- if (best) candidates[[best]]$parameter else if (method == "linear") "-" else mode
    model <- fit_model(method, parameter, points, settings, mode)
    direction <- if (method == "isotonic") model$direction else mode
    if (method == "isotonic") parameter <- direction
    loo <- if (best && method != "spline") candidates[[best]]$score else cross_validation_score(
        observed,
        validation_predictions(method, parameter, points, settings, direction, nrow(points))
    )
    kfold <- cross_validation_score(
        observed,
        validation_predictions(method, parameter, points, settings, direction, settings$CV_FOLDS)
    )
    entries[[method]] <- list(model = model, parameter = parameter, loo = loo, kfold = kfold, candidates = candidates, best = best,
                              gcv = if (method == "spline") candidates[[best]]$score else NULL)
  }
  entries
}
quantiles <- function(residuals) {
  ordered <- sort(residuals)
  vapply(0L:4L, function(k) {
    index <- ((length(ordered) - 1L) * k) %/% 4L
    remainder <- ((length(ordered) - 1L) * k) %% 4L
    value <- ordered[[index + 1L]]
    if (remainder) value <- value + remainder / 4 * (ordered[[index + 2L]] - ordered[[index + 1L]])
    value
  }, 0)
}
residual_runs <- function(residuals) {
  signs <- ifelse(residuals[residuals != 0] > 0, 1L, -1L)
  positive <- sum(signs == 1L)
  negative <- sum(signs == -1L)
  n <- length(signs)
  runs <- 1L + sum(head(signs, -1L) != tail(signs, -1L))
  product <- 2 * positive * negative
  mean <- 1 + product / n
  variance <- product * (product - n) / (n * n * (n - 1L))
  list(runs = runs, positive = positive, negative = negative, z = (runs - mean) / sqrt(variance))
}
turning_count <- function(grid_values) {
  values <- unlist(grid_values, use.names = FALSE)
  differences <- diff(values)
  differences <- differences[differences != 0]
  sum((head(differences, -1L) > 0) != (tail(differences, -1L) > 0))
}
diagnostics <- function(method, model, observed, grid_values, linear_rss) {
  residuals <- observed - model$fitted
  n <- length(observed)
  rss <- ordered_sum(residuals * residuals)
  mean <- ordered_sum(observed) / n
  tss <- ordered_sum((observed - mean) * (observed - mean))
  edf <- model$edf
  df <- if (is.null(edf)) NULL else n - edf
  rse <- if (is.null(edf)) NULL else sqrt(rss / df)
  nonlinear <- if (method != "linear" && !is.null(edf) && edf > 2) ((linear_rss - rss) / (edf - 2)) / (rss / df) else NULL
  residual_mean <- ordered_sum(residuals) / n
  centered <- residuals - residual_mean
  denominator <- ordered_sum(centered * centered)
  acf <- vapply(
      seq_len(5L),
      function(lag) ordered_sum(centered[seq_len(n - lag)] * centered[seq.int(lag + 1L, n)]) / denominator,
      0
  )
  dw <- ordered_sum(diff(residuals) * diff(residuals)) / rss
  list(residuals = residuals, rss = rss, edf = edf, df = df, rse = rse, r2 = 1 - rss / tss, f_nonlinear = nonlinear,
       acf = acf, dw = dw, runs = residual_runs(residuals), largest = which.max(abs(residuals)), quantiles = quantiles(residuals), turning = turning_count(grid_values))
}
agreements <- function(entries, methods, ranking, grid) {
  best <- entries[[ranking[[1L]]]]$grid_values
  result <- list()
  for (method in methods) {
    if (method == ranking[[1L]]) next
    own <- entries[[method]]$grid_values
    indices <- which(vapply(seq_along(grid), function(i) !is.null(own[[i]]) && !is.null(best[[i]]), FALSE))
    differences <- vapply(indices, function(i) abs(own[[i]] - best[[i]]), 0)
    largest <- which.max(differences)
    result[[method]] <- list(count = length(indices), rms = sqrt(ordered_sum(differences * differences) / length(indices)),
                             maximum = differences[[largest]], position = grid[[indices[[largest]]]])
  }
  result
}
spline_slopes <- function(values, grid) {
  values <- unlist(values)
  indices <- seq.int(2L, length(grid) - 1L)
  slopes <- vapply(
      indices,
      function(i) (values[[i + 1L]] - values[[i - 1L]]) / ((grid[[i + 1L]] - grid[[i - 1L]]) / 100),
      0
  )
  hi <- which.max(slopes)
  lo <- which.min(slopes)
  list(
      maximum = slopes[[hi]],
      at_max = grid[[indices[[hi]]]],
      minimum = slopes[[lo]],
      at_min = grid[[indices[[lo]]]]
  )
}
outliers_and_influence <- function(entries, ranking, threshold) {
  method <- ranking[[which(vapply(
      ranking,
      function(name) !is.null(entries[[name]]$model$leverage),
      FALSE
  ))[[1L]]]]
  model <- entries[[method]]$model
  stats <- entries[[method]]$diagnostics
  standardized <- cooks <- rep.int(NA_real_, length(model$leverage))
  eligible <- which(model$leverage < 1)
  for (i in eligible) {
    leverage <- model$leverage[[i]]
    value <- stats$residuals[[i]] / (stats$rse * sqrt(1 - leverage))
    standardized[[i]] <- value
    cooks[[i]] <- value * value * leverage / ((1 - leverage) * model$edf)
  }
  outliers <- eligible[abs(standardized[eligible]) > threshold]
  outliers <- outliers[order(-abs(standardized[outliers]), outliers, method = "radix")]
  influential <- head(eligible[order(-cooks[eligible], eligible, method = "radix")], 3L)
  list(
      method = method,
      standardized = standardized,
      cooks = cooks,
      outliers = outliers,
      influential = influential
  )
}
variability_bands <- function(model, rse, grid, z) {
  lapply(grid, function(position) {
    value <- estimate(model, position)
    if (is.null(value)) return(list(NULL, NULL, NULL, NULL))
    coefficients <- weights(model, position)
    se <- rse * sqrt(ordered_sum(coefficients * coefficients))
    list(value, se, value - z * se, value + z * se)
  })
}
band_summary <- function(entry, positions, bands, z) {
  errors <- vapply(Filter(function(row) !is.null(row[[1L]]), bands), `[[`, 0, 2L)
  stats <- entry$diagnostics
  covered <- 0L
  for (i in seq_along(positions)) {
    coefficients <- weights(entry$model, positions[[i]])
    se <- stats$rse * sqrt(ordered_sum(coefficients * coefficients))
    covered <- covered + as.integer(abs(stats$residuals[[i]]) <= z * sqrt(stats$rse * stats$rse + se * se))
  }
  list(mean_se = ordered_sum(errors) / length(errors), covered = covered)
}
new_minstd <- function(seed) new_model(state = as.numeric(seed))
draw_index <- function(generator, count) {
  generator$state <- (48271 * generator$state) %% 2147483647
  generator$state %% count + 1L
}
bootstrap_intervals <- function(entry, grid, count, trim, generator) {
  model <- entry$model
  residuals <- entry$diagnostics$residuals
  mean <- ordered_sum(residuals) / length(residuals)
  centered <- residuals - mean
  estimates <- lapply(grid, function(position) numeric())
  for (b in seq_len(count)) {
    response <- vapply(
        model$fitted,
        function(value) value + centered[[draw_index(generator, length(centered))]],
        0
    )
    fit <- model$fit_values(response)
    for (i in seq_along(grid)) estimates[[i]] <- c(estimates[[i]], model$evaluate_fit(fit, grid[[i]]))
  }
  lapply(seq_along(grid), function(i) {
    values <- estimates[[i]]
    average <- ordered_sum(values) / count
    se <- sqrt(ordered_sum((values - average) * (values - average)) / (count - 1L))
    ordered <- sort(values)
    list(estimate(model, grid[[i]]), se, ordered[[trim + 1L]], ordered[[count - trim]])
  })
}
analyze_series <- function(points, settings, methods, mode, generator) {
  positions <- points[, 1L]
  values <- points[, 2L] / 100
  count <- settings$GRID_POINTS
  grid <- positions[[1L]] + ((0L:(count - 1L)) * (tail(positions, 1L) - positions[[1L]])) %/% (count - 1L)
  entries <- select_models(points, settings, methods, mode)
  linear_rss <- residual_square(values, entries$linear$model$fitted)
  for (method in methods) {
    entry <- entries[[method]]
    entry$grid_values <- lapply(grid, function(position) estimate(entry$model, position))
    entry$diagnostics <- diagnostics(method, entry$model, values, entry$grid_values, linear_rss)
    entries[[method]] <- entry
  }
  ranking <- methods[order(vapply(entries[methods], `[[`, 0, "loo"), seq_along(methods), method = "radix")]
  bands <- summaries <- list()
  for (method in settings$BAND_METHODS) {
    entry <- entries[[method]]
    bands[[method]] <- variability_bands(entry$model, entry$diagnostics$rse, grid, settings$BAND_Z)
    summaries[[method]] <- band_summary(entry, positions, bands[[method]], settings$BAND_Z)
  }
  bands$spline_bootstrap <- bootstrap_intervals(
      entries$spline,
      grid,
      settings$BOOTSTRAP[[1L]],
      settings$BOOTSTRAP[[2L]],
      generator
  )
  list(points = points, grid = grid, entries = entries, ranking = ranking, agreement = agreements(entries, methods, ranking, grid),
       slope = spline_slopes(entries$spline$grid_values, grid), outlier = outliers_and_influence(
           entries,
           ranking,
           settings$OUTLIER_THRESHOLD
       ),
       bands = bands, band_summary = summaries)
}
real_text <- function(value, places = 4L) {
  if (is.null(value)) return("NA")
  result <- sprintf(paste0("%.", places, "f"), value)
  zero <- sprintf(paste0("%.", places, "f"), 0)
  ifelse(result == paste0("-", zero), zero, result)
}
position_text <- function(value) {
  if (!length(value)) return(character())
  paste0(ifelse(value < 0L, "-", ""), abs(value) %/% 100L, ".", sprintf("%02d", abs(value) %% 100L))
}
real_list <- function(values) paste(vapply(as.list(values), real_text, ""), collapse = " ")
join_blocks <- function(blocks) {
  lines <- character()
  for (block in blocks) {
    if (length(lines)) lines <- c(lines, "")
    lines <- c(lines, block)
  }
  lines
}
method_diagnostic_lines <- function(method, entry, points) {
  stats <- entry$diagnostics
  first <- paste("method", method, "parameter", entry$parameter, "loo", real_text(entry$loo))
  if (method == "spline") first <- paste(first, "gcv", real_text(entry$gcv))
  runs <- stats$runs
  largest <- stats$largest
  lines <- c(first,
             paste0(
                 "  rss ",
                 real_text(stats$rss),
                 " edf ",
                 real_text(stats$edf),
                 " df ",
                 real_text(stats$df),
                 " rse ",
                 real_text(stats$rse),
                 " r2 ",
                 real_text(stats$r2),
                 " f_nonlinear ",
                 real_text(stats$f_nonlinear)
             ),
             paste0("  acf ", real_list(stats$acf), " dw ", real_text(stats$dw)),
             paste0(
                 "  runs ",
                 runs$runs,
                 " positive ",
                 runs$positive,
                 " negative ",
                 runs$negative,
                 " z ",
                 real_text(runs$z)
             ),
             paste0(
                 "  max_residual ",
                 real_text(stats$residuals[[largest]]),
                 " at ",
                 position_text(points[largest, 1L]),
                 " turning ",
                 stats$turning
             ),
             paste0("  quantiles ", real_list(stats$quantiles)))
  if (startsWith(method, "loess")) {
    model <- entry$model
    for (record in model$records) lines <- c(
        lines,
        paste0(
            "  robust ",
            record$iteration,
            " scale ",
            real_text(record$scale),
            " zero_weight ",
            record$zero_count,
            " max_change ",
            real_text(record$change)
        )
    )
    zero_points <- position_text(points[model$rho == 0, 1L])
    lines <- c(
        lines,
        paste0(
            "  zero_weight_points ",
            if (length(zero_points)) paste(zero_points, collapse = " ") else "none"
        )
    )
  }
  lines
}
diagnostics_block <- function(name, analysis, methods, settings) {
  points <- analysis$points
  entries <- analysis$entries
  ranking <- analysis$ranking
  lines <- paste("series", name, "n", nrow(points), "x", position_text(points[1L, 1L]), position_text(points[nrow(points), 1L]),
                 "y", position_text(min(points[, 2L])), position_text(max(points[, 2L])))
  for (method in methods) lines <- c(lines, method_diagnostic_lines(method, entries[[method]], points))
  lines <- c(lines, "ranking")
  for (rank in seq_along(ranking)) {
    method <- ranking[[rank]]
    lines <- c(
        lines,
        paste0(
            "  ",
            rank,
            " ",
            method,
            " ",
            real_text(entries[[method]]$loo),
            " kfold ",
            real_text(entries[[method]]$kfold)
        )
    )
  }
  lines <- c(lines, paste("agreement with", ranking[[1L]]))
  for (method in methods) {
    if (method == ranking[[1L]]) next
    item <- analysis$agreement[[method]]
    lines <- c(
        lines,
        paste0(
            "  ",
            method,
            " points ",
            item$count,
            " rms ",
            real_text(item$rms),
            " max ",
            real_text(item$maximum),
            " at ",
            position_text(item$position)
        )
    )
  }
  slope <- analysis$slope
  lines <- c(
      lines,
      paste(
          "slope spline max",
          real_text(slope$maximum),
          "at",
          position_text(slope$at_max),
          "min",
          real_text(slope$minimum),
          "at",
          position_text(slope$at_min)
      )
  )
  data <- analysis$outlier
  entry <- entries[[data$method]]
  model <- entry$model
  residuals <- entry$diagnostics$residuals
  lines <- c(
      lines,
      paste("outliers method", data$method, "threshold", real_text(settings$OUTLIER_THRESHOLD, 2L))
  )
  for (i in data$outliers) lines <- c(lines, paste0("  x ", position_text(points[i, 1L]), " y ", position_text(points[i, 2L]), " fit ", real_text(model$fitted[[i]]),
                                                  " residual ", real_text(residuals[[i]]), " standardized ", real_text(data$standardized[[i]])))
  if (!length(data$outliers)) lines <- c(lines, "  none")
  lines <- c(lines, paste("influence method", data$method))
  for (i in data$influential) lines <- c(
      lines,
      paste0(
          "  x ",
          position_text(points[i, 1L]),
          " lev ",
          real_text(model$leverage[[i]]),
          " cook ",
          real_text(data$cooks[[i]])
      )
  )
  lines <- c(lines, "bands")
  for (method in settings$BAND_METHODS) {
    summary <- analysis$band_summary[[method]]
    lines <- c(
        lines,
        paste0(
            "  ",
            method,
            " mean_se ",
            real_text(summary$mean_se),
            " coverage ",
            summary$covered,
            " of ",
            nrow(points)
        )
    )
  }
  lines
}
isotonic_block <- function(name, analysis) {
  entry <- analysis$entries$isotonic
  model <- entry$model
  first <- paste("series", name, "direction", model$direction, "mode", model$mode)
  if (model$mode == "auto") first <- paste(
      first,
      "rss_increasing",
      real_text(model$rss_increasing),
      "rss_decreasing",
      real_text(model$rss_decreasing)
  )
  lines <- c(
      first,
      paste(
          "blocks",
          length(model$blocks),
          "rss",
          real_text(entry$diagnostics$rss),
          "loo",
          real_text(entry$loo)
      )
  )
  for (number in seq_along(model$blocks)) {
    block <- model$blocks[[number]]
    lines <- c(lines, paste("block", number, "x", position_text(model$positions[[block[[1L]]]]), position_text(model$positions[[block[[2L]]]]),
                            "count", block[[4L]], "value", real_text(block[[3L]] / (100 * block[[4L]]))))
  }
  lines
}
framed <- function(grid) {
  border <- paste0("+", strrep("-", ncol(grid)), "+")
  c(
      border,
      vapply(seq_len(nrow(grid)), function(row) paste0("|", paste(grid[row, ], collapse = ""), "|"), ""),
      border
  )
}
histogram_lines <- function(standardized) {
  counts <- integer(14L)
  for (value in standardized[!is.na(standardized)]) {
    index <- if (value < -3) 1L else if (value >= 3) 14L else 2L + floor((value + 3) / 0.5)
    counts[[index]] <- counts[[index]] + 1L
  }
  vapply(seq_along(counts), function(i) {
    lower <- if (i == 1L) "-inf" else real_text(-3 + 0.5 * (i - 2L), 2L)
    upper <- if (i == 14L) "inf" else real_text(-3 + 0.5 * (i - 1L), 2L)
    paste0(lower, " ", upper, " ", counts[[i]], " |", strrep("#", counts[[i]]))
  }, "")
}
plot_block <- function(name, analysis, settings) {
  points <- analysis$points
  width <- settings$PLOT_SIZE[[1L]]
  height <- settings$PLOT_SIZE[[2L]]
  xa <- points[1L, 1L]
  xb <- points[nrow(points), 1L]
  ya <- min(points[, 2L])
  yb <- max(points[, 2L])
  columns <- pmin(width - 1L, (width * (points[, 1L] - xa)) %/% (xb - xa)) + 1L
  grid <- matrix(" ", height, width)
  for (i in seq_len(nrow(points))) {
    row <- min(height - 1L, (height * (yb - points[i, 2L])) %/% (yb - ya)) + 1L
    grid[row, columns[[i]]] <- "."
  }
  for (number in seq_along(settings$PLOT_METHODS)) {
    method <- settings$PLOT_METHODS[[number]]
    for (column in 0L:(width - 1L)) {
      position <- xa + ((2L * column + 1L) * (xb - xa)) %/% (2L * width)
      value <- estimate(analysis$entries[[method]]$model, position)
      if (is.null(value)) next
      pi <- height * (yb / 100 - value) / (yb / 100 - ya / 100)
      row <- max(0, min(height - 1L, floor(pi))) + 1L
      digit <- as.character(number)
      grid[row, column + 1L] <- if (grid[row, column + 1L] %in% c(" ", ".", digit)) digit else "*"
    }
  }
  legend <- paste(seq_along(settings$PLOT_METHODS), settings$PLOT_METHODS, collapse = " ")
  lines <- c(paste("plot", name, "size", paste0(width, "x", height), "x", position_text(xa), position_text(xb), "y", position_text(ya), position_text(yb)),
             paste("legend . data", legend), framed(grid), paste(
                 "cells data",
                 sum(grid == "."),
                 "curve",
                 sum(grid %in% as.character(1L:9L)),
                 "overlap",
                 sum(grid == "*")
             ))
  method <- analysis$ranking[[1L]]
  residuals <- analysis$entries[[method]]$diagnostics$residuals
  limit <- max(abs(residuals))
  grid <- matrix(" ", height, width)
  grid[height %/% 2L + 1L, ] <- "-"
  for (i in seq_along(residuals)) {
    row <- max(0, min(height - 1L, floor(height * ((limit - residuals[[i]]) / (2 * limit))))) + 1L
    grid[row, columns[[i]]] <- "o"
  }
  c(lines, "", paste("residuals", name, "method", method, "limit", real_text(limit)), framed(grid), "",
    paste(
        "histogram",
        name,
        "method",
        analysis$outlier$method
    ), histogram_lines(analysis$outlier$standardized))
}
main <- function() {
  data <- read_dataset()
  series <- data$series
  settings <- data$settings
  methods <- methods_in_order(settings)
  generator <- new_minstd(settings$BOOTSTRAP[[3L]])
  analyses <- list()
  for (index in seq_along(series)) {
    name <- names(series)[[index]]
    analyses[[name]] <- analyze_series(
        series[[index]],
        settings,
        methods,
        settings$ISOTONIC[[index]],
        generator
    )
  }
  selection <- "series,method,parameter,score,edf,selected"
  fits <- predictions <- paste0("series,x,", paste(methods, collapse = ","))
  bands <- "series,method,x,fit,se,lower,upper"
  for (name in names(analyses)) {
    analysis <- analyses[[name]]
    for (method in methods) {
      entry <- analysis$entries[[method]]
      for (i in seq_along(entry$candidates)) {
        candidate <- entry$candidates[[i]]
        selection <- c(
            selection,
            paste(
                c(
                    name,
                    method,
                    candidate$parameter,
                    real_text(candidate$score),
                    real_text(candidate$edf),
                    as.integer(i == entry$best)
                ),
                collapse = ","
            )
        )
      }
    }
    for (i in seq_along(analysis$grid)) {
      values <- vapply(methods, function(method) real_text(analysis$entries[[method]]$grid_values[[i]]), "")
      fits <- c(fits, paste(c(name, position_text(analysis$grid[[i]]), values), collapse = ","))
    }
    for (method in c(settings$BAND_METHODS, "spline_bootstrap")) {
      for (i in seq_along(analysis$grid)) {
        values <- vapply(analysis$bands[[method]][[i]], real_text, "")
        bands <- c(bands, paste(c(name, method, position_text(analysis$grid[[i]]), values), collapse = ","))
      }
    }
  }
  for (test in data$tests) {
    values <- vapply(
        methods,
        function(method) real_text(estimate(analyses[[test$name]]$entries[[method]]$model, test$position)),
        ""
    )
    predictions <- c(predictions, paste(c(test$name, position_text(test$position), values), collapse = ","))
  }
  outputs <- list(
    "selection.csv" = selection, "fits.csv" = fits, "predictions.csv" = predictions, "bands.csv" = bands,
    "diagnostics.txt" = join_blocks(lapply(
        names(analyses),
        function(name) diagnostics_block(name, analyses[[name]], methods, settings)
    )),
    "isotonic.txt" = join_blocks(lapply(
        names(analyses),
        function(name) isotonic_block(name, analyses[[name]])
    )),
    "plots.txt" = join_blocks(lapply(
        settings$PLOT_SERIES,
        function(name) plot_block(name, analyses[[name]], settings)
    ))
  )
  dir.create("output", showWarnings = FALSE)
  for (name in names(outputs)) writeLines(outputs[[name]], file.path("output", name), useBytes = TRUE)
}
main()
