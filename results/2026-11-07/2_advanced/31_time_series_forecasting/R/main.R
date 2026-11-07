for (file in c(
    "series_io",
    "decomposition",
    "smoothing",
    "autoregression",
    "evaluation"
)) source(paste0(file, ".R"))

METHODS <- c(
    "naive",
    "snaive",
    "drift",
    "ses",
    "holt",
    "damped",
    "hw_add",
    "hw_mult",
    "decomp_add",
    "decomp_mult",
    "ar"
)
MODELS <- c(METHODS, "combo")
SMOOTHING_PARAMETERS <- list(
    ses = "alpha",
    holt = c("alpha", "beta"),
    damped = c("alpha", "beta", "phi"),
    hw_add = c("alpha", "beta", "gamma"),
    hw_mult = c("alpha", "beta", "gamma")
)
INTERVAL_FIELDS <- c("forecast", "lo80", "hi80", "lo95", "hi95")
ACCURACY_FIELDS <- c(
    "me",
    "mae",
    "rmse",
    "mape",
    "smape",
    "mase",
    "fva",
    "cv_rmse",
    "cover80",
    "cover95",
    "winkler80",
    "winkler95",
    "rank"
)
line_text <- function(...) paste(c(...), collapse = " ")
rmse <- function(errors) sqrt(ordered_sum(errors * errors) / length(errors))
interpolate_missing <- function(raw) {
    values <- as.numeric(raw)
    left <- 1L
    while (left < length(raw)) {
        right <- left + 1L
        while (is.na(raw[right])) right <- right + 1L
        if (right > left + 1L) for (t in seq.int(
            left + 1L,
            right - 1L
        )) values[t] <- raw[left] + (raw[right] - raw[left]) * (t - left) / (right - left)
        left <- right
    }
    values
}
future_periods <- function(last, horizon) {
    periods <- character(horizon)
    for (i in seq_len(horizon)) {
        last <- next_month(last)
        periods[i] <- last
    }
    periods
}
prepare_series <- function(record, settings) {
    season <- settings$season
    values <- interpolate_missing(record$raw)
    missing <- which(is.na(record$raw))
    decomposition <- decompose(values, season)
    trend <- decomposition$trend
    additive <- decomposition$additive
    residuals <- decomposition$residual_add
    defined <- decomposition$defined
    average <- series_mean(residuals[defined])
    deviation <- sqrt(sample_variance(residuals[defined]))
    past <- outliers <- list()
    for (t in seq_along(record$periods)) {
        event <- record$events[[record$periods[t]]]
        if (!is.null(event)) past[[as.character(t)]] <- event
    }
    for (t in defined) if (!(t %in% missing) && !(as.character(t) %in% names(past)) && abs(residuals[t] - average) > settings$outlier * deviation) outliers[[as.character(t)]] <- (residuals[t] - average) / deviation
    grouped <- list()
    for (t in as.integer(names(past))) {
        kind <- past[[as.character(t)]]
        grouped[[kind]] <- c(grouped[[kind]], t)
    }
    lifts <- lapply(
        grouped,
        function(times) list(
            occurrences = length(times),
            lift = series_mean(values[times] / (trend[times] + additive[(times - 1L) %% season + 1L]))
        )
    )
    corrected <- values
    for (t in seq_along(values)) if (as.character(t) %in% c(
        names(past),
        names(outliers)
    )) corrected[t] <- trend[t] + additive[(t - 1L) %% season + 1L]
    variance_r <- sample_variance(residuals[defined])
    variance_t <- sample_variance(trend[defined] + residuals[defined])
    variance_s <- sample_variance(additive[(defined - 1L) %% season + 1L] + residuals[defined])
    list(name = record$name, periods = record$periods, raw = record$raw, values = values, corrected = corrected, future_periods = future_periods(tail(record$periods, 1L), settings$horizon), missing = missing, past = past, outliers = outliers, kinds = names(grouped), lifts = lifts, decomposition = decomposition,
         strength_trend = max(0, 1 - variance_r / variance_t), strength_seasonal = max(
             0,
             1 - variance_r / variance_s
         ))
}
decomposition_prediction <- function(model, time) {
    base <- model$intercept + model$slope * (time + 1L)
    seasonal <- model$seasonal[time %% model$season + 1L]
    if (model$name == "decomp_add") base + seasonal else base * seasonal
}
fit_ar <- function(model, settings) {
    transformed <- lapply(DIFFERENCE_KINDS, function(kind) difference(model$series, model$season, kind))
    variances <- vapply(transformed, function(item) autocorrelation(item$values, 0L)$variance, 0)
    chosen <- which.min(variances)
    values <- transformed[[chosen]]$values
    acf <- autocorrelation(values, settings$max_lag)
    dl <- durbin_levinson(acf$correlations)
    aic <- vapply(
        seq.int(0L, settings$max_ar),
        function(p) length(values) * log(acf$variance * dl$variances[p + 1L]) + 2L * p,
        0
    )
    order <- which.min(aic) - 1L
    model$kind <- DIFFERENCE_KINDS[chosen]
    model$differenced <- values
    model$offset <- transformed[[chosen]]$offset
    model$average <- acf$mean
    model$order <- order
    model$variances <- variances
    model$sigma2 <- acf$variance * dl$variances[order + 1L]
    model$aic <- aic
    model$coefficients <- dl$coefficients[[order + 1L]]
    model$correlations <- acf$correlations
    model$partial <- dl$partial
    model$residuals <- ar_residuals(values, acf$mean, model$coefficients)
    model
}
fit_method <- function(name, values, settings) {
    model <- list(name = name, series = values, season = settings$season)
    season <- settings$season
    n <- length(values)
    if (name == "naive") model$residuals <- values[-1L] - values[-n] else if (name == "snaive") {
        times <- seq.int(season + 1L, n)
        model$residuals <- values[times] - values[times - season]
    } else if (name == "drift") {
        model$slope <- (values[n] - values[1L]) / (n - 1L)
        model$residuals <- values[-1L] - values[-n] - model$slope
    } else if (name %in% names(SMOOTHING_PARAMETERS)) {
        parameters_names <- SMOOTHING_PARAMETERS[[name]]
        best <- NULL
        visit <- function(depth, parameters) {
            if (depth <= length(parameters_names)) {
                key <- parameters_names[depth]
                for (value in settings[[key]]) {
                    parameters[[key]] <- value
                    visit(depth + 1L, parameters)
                }
            } else {
                result <- smoothing_recurse(name, values, season, parameters)
                score <- ordered_sum(result$errors * result$errors)
                if (is.null(best) || score < best$score) best <<- list(
                    score = score,
                    parameters = parameters,
                    residuals = result$errors,
                    states = result$states
                )
            }
        }
        visit(1L, list())
        model$parameters <- best$parameters
        model$residuals <- best$residuals
        model$states <- best$states
    } else if (name %in% c("decomp_add", "decomp_mult")) {
        components <- decompose(values, season)
        additive <- name == "decomp_add"
        model$seasonal <- if (additive) components$additive else components$multiplicative
        seasonal <- model$seasonal[(seq_along(values) - 1L) %% season + 1L]
        adjusted <- if (additive) values - seasonal else values / seasonal
        line <- least_squares_line(adjusted)
        model$intercept <- unname(line[1L])
        model$slope <- unname(line[2L])
        model$residuals <- values - vapply(
            seq.int(0L, n - 1L),
            function(t) decomposition_prediction(model, t),
            0
        )
    } else model <- fit_ar(model, settings)
    model
}
combination_model <- function(models, values, season) list(
    name = "combo",
    series = values,
    season = season,
    members = models
)
forecast <- function(model, origin, steps) {
    name <- model$name
    values <- model$series
    season <- model$season
    if (name == "combo") {
        predictions <- lapply(model$members, function(member) forecast(member, origin, steps))
        return(vapply(
            seq_len(steps),
            function(i) ordered_sum(vapply(predictions, function(row) row[i], 0)) / length(predictions),
            0
        ))
    }
    if (name == "naive") return(rep(values[origin], steps))
    if (name == "snaive") return(values[origin - season + (seq_len(steps) - 1L) %% season + 1L])
    if (name == "drift") {
        slope <- (values[origin] - values[1L]) / (origin - 1L)
        return(values[origin] + seq_len(steps) * slope)
    }
    if (name %in% names(SMOOTHING_PARAMETERS)) return(smoothing_forecast(
        name,
        model$states[[origin + 1L]],
        model$parameters,
        origin,
        steps,
        season
    ))
    if (name %in% c("decomp_add", "decomp_mult")) return(vapply(
        seq_len(steps),
        function(step) decomposition_prediction(model, origin + step - 1L),
        0
    ))
    ar_forecast(
        values,
        model$differenced,
        model$offset,
        model$kind,
        model$average,
        model$coefficients,
        origin,
        steps,
        season
    )
}
cross_validate <- function(model, settings) {
    values <- model$series
    horizon <- settings$horizon
    counts <- integer(horizon)
    squared <- absolute <- numeric(horizon)
    for (origin in seq.int(settings$cv_start, length(values) - 1L)) {
        predictions <- forecast(model, origin, min(horizon, length(values) - origin))
        for (i in seq_along(predictions)) {
            error <- values[origin + i] - predictions[i]
            counts[i] <- counts[i] + 1L
            squared[i] <- squared[i] + error * error
            absolute[i] <- absolute[i] + abs(error)
        }
    }
    holdout <- settings$holdout
    list(
        counts = counts,
        sigma = sqrt(squared / counts),
        mae = absolute / counts,
        cv_rmse = sqrt(ordered_sum(squared[seq_len(holdout)]) / sum(counts[seq_len(holdout)]))
    )
}
interval_rows <- function(predicted, sigma, coefficients, multipliers = rep(1, length(predicted))) {
    low <- coefficients[1L]
    high <- coefficients[2L]
    lapply(
        seq_along(predicted),
        function(i) list(
            forecast = predicted[i] * multipliers[i],
            lo80 = (predicted[i] - low * sigma[i]) * multipliers[i],
            hi80 = (predicted[i] + low * sigma[i]) * multipliers[i],
            lo95 = (predicted[i] - high * sigma[i]) * multipliers[i],
            hi95 = (predicted[i] + high * sigma[i]) * multipliers[i]
        )
    )
}
evaluate_holdout <- function(models, cvs, actual, training, settings) {
    scale <- seasonal_scale(training, settings$season)
    metrics <- intervals <- list()
    for (name in MODELS) {
        predicted <- forecast(models[[name]], length(training), length(actual))
        rows <- interval_rows(predicted, cvs[[name]]$sigma, settings$interval)
        intervals[[name]] <- rows
        measures <- accuracy(actual, predicted, scale)
        measures$cv_rmse <- cvs[[name]]$cv_rmse
        measures$cover80 <- sum(vapply(
            seq_along(actual),
            function(i) rows[[i]]$lo80 <= actual[i] && actual[i] <= rows[[i]]$hi80,
            FALSE
        ))
        measures$cover95 <- sum(vapply(
            seq_along(actual),
            function(i) rows[[i]]$lo95 <= actual[i] && actual[i] <= rows[[i]]$hi95,
            FALSE
        ))
        measures$winkler80 <- ordered_sum(vapply(
            seq_along(actual),
            function(i) winkler(actual[i], rows[[i]]$lo80, rows[[i]]$hi80, 10),
            0
        )) / length(actual)
        measures$winkler95 <- ordered_sum(vapply(
            seq_along(actual),
            function(i) winkler(actual[i], rows[[i]]$lo95, rows[[i]]$hi95, 40),
            0
        )) / length(actual)
        metrics[[name]] <- measures
    }
    naive_mae <- metrics$naive$mae
    for (name in MODELS) metrics[[name]]$fva <- 100 * (naive_mae - metrics[[name]]$mae) / naive_mae
    ranking <- rank_models(MODELS, metrics)
    for (rank in seq_along(ranking)) metrics[[ranking[rank]]]$rank <- rank
    list(metrics = metrics, intervals = intervals, best = ranking[1L])
}
inventory_plan <- function(model, demands, policy, settings) {
    lead <- policy$lead_time
    review <- policy$review
    protection <- lead + review
    values <- model$series
    errors <- vapply(seq.int(settings$cv_start, length(values) - protection), function(origin) {
        predictions <- forecast(model, origin, protection)
        ordered_sum(values[origin + seq_along(predictions)] - predictions)
    }, 0)
    safety <- policy$service * rmse(errors)
    reviews <- seq.int(1L, length(demands) - protection + 1L, review)
    last <- tail(reviews, 1L) - 1L + protection
    on_hand <- as.numeric(policy$on_hand)
    outstanding <- orders <- ordered <- 0L
    receipts <- list()
    rows <- list()
    for (step in seq_len(last)) {
        key <- as.character(step)
        receipt <- if (is.null(receipts[[key]])) 0L else receipts[[key]]
        receipts[[key]] <- NULL
        on_hand <- on_hand + receipt
        outstanding <- outstanding - receipt
        review_row <- NULL
        if (step %in% reviews) {
            position <- on_hand + outstanding
            target <- ordered_sum(demands[seq.int(step, step + protection - 1L)]) + safety
            quantity <- as.integer(max(0, ceiling(target - position)))
            review_row <- list(position = position, target = target, order = quantity)
            if (quantity > 0L) {
                orders <- orders + 1L
                ordered <- ordered + quantity
                outstanding <- outstanding + quantity
                receipts[[as.character(step + lead)]] <- quantity
            }
        }
        on_hand <- on_hand - demands[step]
        status <- if (on_hand < 0) "short" else if (on_hand < safety) "low" else "ok"
        rows[[step]] <- list(
            step = step,
            receipt = receipt,
            demand = demands[step],
            review = review_row,
            on_hand = on_hand,
            status = status
        )
    }
    amounts <- vapply(rows, function(row) row$on_hand, 0)
    list(
        safety = safety,
        rows = rows,
        orders = orders,
        ordered = ordered,
        short_periods = sum(vapply(rows, function(row) row$status == "short", FALSE)),
        lowest = min(amounts),
        average = series_mean(amounts)
    )
}
yearly_totals <- function(periods, actual, future, demands) {
    years <- sort(unique(substr(c(periods, future), 1L, 4L)))
    rows <- list()
    previous <- NULL
    for (year in years) {
        actual_values <- actual[substr(periods, 1L, 4L) == year]
        forecast_values <- demands[substr(future, 1L, 4L) == year]
        actual_total <- ordered_sum(actual_values)
        forecast_total <- ordered_sum(forecast_values)
        total <- actual_total + forecast_total
        complete <- length(actual_values) + length(forecast_values) == 12L
        growth <- if (complete && !is.null(previous) && previous$complete) 100 * (total - previous$total) / previous$total else NA_real_
        row <- list(
            year = year,
            actual_months = length(actual_values),
            actual = actual_total,
            forecast_months = length(forecast_values),
            forecast = forecast_total,
            total = total,
            growth = growth,
            complete = complete
        )
        rows <- c(rows, list(row))
        previous <- row
    }
    rows
}
residual_diagnostics <- function(errors, lags) {
    n <- length(errors)
    average <- series_mean(errors)
    centered <- errors - average
    squared <- ordered_sum(centered * centered)
    m2 <- squared / n
    m3 <- ordered_sum(centered * centered * centered) / n
    m4 <- ordered_sum(centered * centered * centered * centered) / n
    sd <- sqrt(squared / (n - 1L))
    dw <- ordered_sum((errors[-1L] - errors[-n]) * (errors[-1L] - errors[-n])) / ordered_sum(errors * errors)
    skewness <- m3 / (m2 * sqrt(m2))
    kurtosis <- m4 / (m2 * m2) - 3
    jb <- n / 6 * (skewness * skewness + kurtosis * kurtosis / 4)
    list(
        count = n,
        mean = average,
        sd = sd,
        dw = dw,
        skewness = skewness,
        kurtosis = kurtosis,
        jb = jb,
        ljung_box = ljung_box(errors, lags)
    )
}
analyze <- function(record, settings) {
    data <- prepare_series(record, settings)
    training_count <- length(data$values) - settings$holdout
    training <- data$corrected[seq_len(training_count)]
    actual <- data$values[seq.int(training_count + 1L, length(data$values))]
    models <- setNames(lapply(METHODS, function(name) fit_method(name, training, settings)), METHODS)
    cvs <- lapply(models, cross_validate, settings = settings)
    selected <- METHODS[order(
        vapply(cvs, function(cv) cv$cv_rmse, 0),
        seq_along(METHODS)
    )[seq_len(settings$combo)]]
    members <- METHODS[METHODS %in% selected]
    models$combo <- combination_model(models[members], training, settings$season)
    cvs$combo <- cross_validate(models$combo, settings)
    evaluation <- evaluate_holdout(models, cvs, actual, training, settings)
    final_names <- if (evaluation$best == "combo") members else evaluation$best
    final_fits <- lapply(final_names, function(name) fit_method(name, data$corrected, settings))
    final <- if (evaluation$best == "combo") combination_model(
        final_fits,
        data$corrected,
        settings$season
    ) else final_fits[[1L]]
    final_cv <- cross_validate(final, settings)
    future <- forecast(final, length(data$values), settings$horizon)
    multipliers <- vapply(data$future_periods, function(period) {
        kind <- record$events[[period]]
        if (is.null(kind)) 1 else data$lifts[[kind]]$lift
    }, 0)
    future_rows <- interval_rows(future, final_cv$sigma, settings$interval, multipliers)
    demands <- vapply(future_rows, function(row) row$forecast, 0)
    c(
        data,
        list(
            training_count = training_count,
            models = models,
            cv = cvs,
            members = members,
            metrics = evaluation$metrics,
            intervals = evaluation$intervals,
            best = evaluation$best,
            final_fits = final_fits,
            future_rows = future_rows,
            policy = record$policy,
            plan = inventory_plan(final, demands, record$policy, settings),
            years = yearly_totals(data$periods, data$values, data$future_periods, demands),
            residual_diagnostics = setNames(
                lapply(
                    METHODS,
                    function(name) residual_diagnostics(models[[name]]$residuals, settings$ljung_box)
                ),
                METHODS
            )
        )
    )
}
model_lines <- function(model) {
    name <- model$name
    common <- line_text("rmse", real_format(rmse(model$residuals)), "residuals", length(model$residuals))
    if (name %in% c("naive", "snaive")) return(line_text(name, common))
    if (name == "drift") return(line_text("drift", "slope", real_format(model$slope), common))
    if (name %in% names(SMOOTHING_PARAMETERS)) {
        parameters <- unlist(
            lapply(SMOOTHING_PARAMETERS[[name]], function(key) c(key, real_format(model$parameters[[key]]))),
            use.names = FALSE
        )
        state <- tail(model$states, 1L)[[1L]]
        line <- line_text(name, parameters, common, "level", real_format(state$level))
        if (name != "ses") line <- line_text(line, "slope", real_format(state$slope))
        lines <- line
        if (!is.null(state$components)) {
            origin <- length(model$series)
            values <- state$components[(origin + seq.int(0L, model$season - 1L)) %% model$season + 1L]
            lines <- c(lines, line_text(name, "seasonal", vapply(values, real_format, "")))
        }
        return(lines)
    }
    if (name %in% c("decomp_add", "decomp_mult")) return(c(
        line_text(name, "intercept", real_format(model$intercept), "slope", real_format(model$slope), common),
        line_text(name, "seasonal", vapply(model$seasonal, real_format, ""))
    ))
    variance <- unlist(
        lapply(
            seq_along(DIFFERENCE_KINDS),
            function(i) c(DIFFERENCE_KINDS[i], real_format(model$variances[i]))
        ),
        use.names = FALSE
    )
    coefficients <- if (length(model$coefficients)) vapply(model$coefficients, real_format, "") else "none"
    c(
        line_text("ar", "variance", variance),
        line_text(
            "ar",
            "difference",
            model$kind,
            "n",
            length(model$differenced),
            "mean",
            real_format(model$average),
            "order",
            model$order,
            "sigma2",
            real_format(model$sigma2),
            common
        ),
        line_text("ar", "aic", vapply(model$aic, real_format, "")),
        line_text("ar", "coefficients", coefficients)
    )
}
decomposition_lines <- function(analyses, settings) {
    lines <- "series,period,value,cleaned,trend,seasonal_add,residual_add,seasonal_mult,residual_mult,flag"
    for (data in analyses) {
        decomposition <- data$decomposition
        for (t in seq_along(data$periods)) {
            key <- as.character(t)
            flag <- if (key %in% names(data$past)) data$past[[key]] else if (t %in% data$missing) "missing" else if (key %in% names(data$outliers)) "outlier" else "ok"
            j <- (t - 1L) %% settings$season + 1L
            values <- c(
                data$values[t],
                data$corrected[t],
                decomposition$trend[t],
                decomposition$additive[j],
                decomposition$residual_add[t],
                decomposition$multiplicative[j],
                decomposition$residual_mult[t]
            )
            lines <- c(
                lines,
                paste(c(data$name, data$periods[t], vapply(values, real_format, ""), flag), collapse = ",")
            )
        }
    }
    lines
}
fitted_lines <- function(analyses, settings) {
    lines <- character()
    add <- function(...) lines <<- c(lines, line_text(...))
    for (data in analyses) {
        add("series", data$name)
        add(
            "data",
            "observations",
            length(data$values),
            "train",
            data$training_count,
            "holdout",
            settings$holdout,
            "missing",
            length(data$missing),
            "outliers",
            length(data$outliers),
            "events",
            length(data$past)
        )
        for (kind in data$kinds) {
            lift <- data$lifts[[kind]]
            add("event", kind, "occurrences", lift$occurrences, "lift", real_format(lift$lift))
        }
        for (t in sort(as.integer(names(data$outliers)))) add(
            "outlier",
            data$periods[t],
            "value",
            real_format(data$values[t]),
            "expected",
            real_format(data$corrected[t]),
            "score",
            real_format(data$outliers[[as.character(t)]])
        )
        add(
            "strength",
            "trend",
            real_format(data$strength_trend),
            "seasonal",
            real_format(data$strength_seasonal)
        )
        for (name in METHODS) lines <- c(lines, model_lines(data$models[[name]]))
        add("combo", "members", data$members)
        add("best", data$best, "rmse", real_format(data$metrics[[data$best]]$rmse))
        for (model in data$final_fits) lines <- c(lines, paste("final", model_lines(model)))
    }
    lines
}
forecast_lines <- function(analyses) {
    lines <- "series,stage,method,period,actual,forecast,lo80,hi80,lo95,hi95"
    for (data in analyses) {
        for (method in MODELS) for (i in seq_along(data$intervals[[method]])) {
            row <- data$intervals[[method]][[i]]
            index <- data$training_count + i
            fields <- vapply(INTERVAL_FIELDS, function(key) real_format(row[[key]]), "")
            lines <- c(
                lines,
                paste(
                    c(data$name, "holdout", method, data$periods[index], data$raw[index], fields),
                    collapse = ","
                )
            )
        }
        for (i in seq_along(data$future_rows)) {
            row <- data$future_rows[[i]]
            fields <- vapply(INTERVAL_FIELDS, function(key) real_format(row[[key]]), "")
            lines <- c(
                lines,
                paste(c(data$name, "future", data$best, data$future_periods[i], "NA", fields), collapse = ",")
            )
        }
    }
    lines
}
accuracy_lines <- function(analyses) {
    lines <- paste(c("series", "method", ACCURACY_FIELDS), collapse = ",")
    for (data in analyses) for (method in MODELS) {
        metrics <- data$metrics[[method]]
        fields <- vapply(
            ACCURACY_FIELDS,
            function(key) if (key %in% c(
                "cover80",
                "cover95",
                "rank"
            )) as.character(metrics[[key]]) else real_format(metrics[[key]]),
            ""
        )
        lines <- c(lines, paste(c(data$name, method, fields), collapse = ","))
    }
    lines
}
cv_lines <- function(analyses) {
    lines <- "series,method,step,origins,mae,rmse"
    for (data in analyses) for (method in MODELS) {
        cv <- data$cv[[method]]
        for (i in seq_along(cv$counts)) lines <- c(
            lines,
            paste(
                data$name,
                method,
                i,
                cv$counts[i],
                real_format(cv$mae[i]),
                real_format(cv$sigma[i]),
                sep = ","
            )
        )
    }
    lines
}
correlation_bar <- function(value, band) {
    width <- as.integer(floor(abs(value) * 20 + 0.5))
    threshold <- as.integer(floor(band * 20 + 0.5))
    bar <- rep(" ", 41L)
    bar[c(21L - threshold, 21L + threshold)] <- ":"
    bar[21L] <- "|"
    if (width > 0L && value > 0) bar[seq.int(22L, 21L + width)] <- "#"
    if (width > 0L && value < 0) bar[seq.int(21L - width, 20L)] <- "#"
    paste(bar, collapse = "")
}
correlogram_lines <- function(analyses) {
    lines <- character()
    add <- function(...) lines <<- c(lines, line_text(...))
    for (data in analyses) {
        ar <- data$models$ar
        n <- length(ar$differenced)
        band <- 2 / sqrt(n)
        add("series", data$name, "difference", ar$kind, "n", n, "band", real_format(band))
        for (label in c("acf", "pacf")) {
            sequence <- if (label == "acf") ar$correlations else ar$partial
            for (lag in seq_len(length(sequence) - 1L)) {
                value <- sequence[lag + 1L]
                line <- paste0(
                    label,
                    " ",
                    sprintf("%2d", lag),
                    " ",
                    sprintf("%7s", real_format(value)),
                    " [",
                    correlation_bar(value, band),
                    "]",
                    if (abs(value) > band) " *" else ""
                )
                lines <- c(lines, line)
            }
        }
        for (method in METHODS) {
            stats <- data$residual_diagnostics[[method]]
            add(
                "residuals",
                method,
                "n",
                stats$count,
                "mean",
                real_format(stats$mean),
                "sd",
                real_format(stats$sd),
                "dw",
                real_format(stats$dw),
                "skewness",
                real_format(stats$skewness),
                "kurtosis",
                real_format(stats$kurtosis),
                "jb",
                real_format(stats$jb)
            )
            parts <- unlist(
                lapply(
                    stats$ljung_box,
                    function(row) c("lag", row$lag, "q", real_format(row$q), "p", real_format(row$p))
                ),
                use.names = FALSE
            )
            add("ljung_box", method, parts)
        }
    }
    lines
}
forecast_chart <- function(row, low, high) {
    column <- function(value) as.integer(floor((value - low) / (high - low) * 60 + 0.5)) + 1L
    cells <- rep(" ", 61L)
    cells[seq.int(column(row$lo95), column(row$hi95))] <- "-"
    cells[seq.int(column(row$lo80), column(row$hi80))] <- "="
    cells[column(row$forecast)] <- "o"
    if (!is.na(row$actual)) cells[column(row$actual)] <- "*"
    paste(cells, collapse = "")
}
seasonal_profile <- function(value, peak) {
    width <- as.integer(floor(abs(value - 1) / peak * 30 + 0.5))
    cells <- rep(" ", 61L)
    cells[31L] <- "|"
    if (width > 0L && value > 1) cells[seq.int(32L, 31L + width)] <- "#"
    if (width > 0L && value < 1) cells[seq.int(31L - width, 30L)] <- "#"
    paste(cells, collapse = "")
}
chart_lines <- function(analyses) {
    lines <- character()
    add <- function(...) lines <<- c(lines, line_text(...))
    for (data in analyses) {
        rows <- list()
        for (i in seq_along(data$intervals[[data$best]])) {
            index <- data$training_count + i
            rows <- c(
                rows,
                list(c(
                    data$intervals[[data$best]][[i]],
                    list(period = data$periods[index], actual = data$values[index])
                ))
            )
        }
        for (i in seq_along(data$future_rows)) rows <- c(
            rows,
            list(c(data$future_rows[[i]], list(period = data$future_periods[i], actual = NA_real_)))
        )
        actual <- vapply(rows, function(row) row$actual, 0)
        actual <- actual[!is.na(actual)]
        low <- min(c(vapply(rows, function(row) row$lo95, 0), actual))
        high <- max(c(vapply(rows, function(row) row$hi95, 0), actual))
        add("chart", data$name, "method", data$best)
        add("scale", "low", real_format(low), "high", real_format(high))
        for (row in rows) lines <- c(lines, paste0(row$period, " |", forecast_chart(row, low, high), "|"))
        seasonal <- data$decomposition$multiplicative
        peak <- max(abs(seasonal - 1))
        add("profile", "peak", real_format(peak))
        for (i in seq_along(seasonal)) lines <- c(
            lines,
            paste0(
                "season ",
                sprintf("%2d", i),
                " ",
                real_format(seasonal[i]),
                " [",
                seasonal_profile(seasonal[i], peak),
                "]"
            )
        )
    }
    lines
}
plan_lines <- function(analyses) {
    lines <- character()
    add <- function(...) lines <<- c(lines, line_text(...))
    for (data in analyses) {
        policy <- data$policy
        plan <- data$plan
        add("series", data$name, "method", data$best)
        add(
            "policy",
            "on_hand",
            policy$on_hand,
            "lead_time",
            policy$lead_time,
            "review",
            policy$review,
            "service",
            real_format(policy$service),
            "safety_stock",
            real_format(plan$safety)
        )
        for (row in plan$rows) {
            period <- data$future_periods[row$step]
            if (!is.null(row$review)) add(
                "review",
                period,
                "position",
                real_format(row$review$position),
                "target",
                real_format(row$review$target),
                "order",
                row$review$order
            )
            add(
                "period",
                period,
                "demand",
                real_format(row$demand),
                "receipt",
                row$receipt,
                "on_hand",
                real_format(row$on_hand),
                "status",
                row$status
            )
        }
        add(
            "summary",
            "orders",
            plan$orders,
            "ordered",
            plan$ordered,
            "short_periods",
            plan$short_periods,
            "lowest",
            real_format(plan$lowest),
            "average",
            real_format(plan$average)
        )
        for (year in data$years) add(
            "year",
            year$year,
            "actual_months",
            year$actual_months,
            "actual",
            real_format(year$actual),
            "forecast_months",
            year$forecast_months,
            "forecast",
            real_format(year$forecast),
            "total",
            real_format(year$total),
            "growth",
            real_format(year$growth)
        )
    }
    lines
}
main <- function() {
    options(scipen = 999)
    inputs <- read_inputs()
    settings <- inputs$settings
    analyses <- lapply(inputs$records, analyze, settings = settings)
    outputs <- list(
        "decomposition.csv" = decomposition_lines(analyses, settings),
        "models.txt" = fitted_lines(analyses, settings),
        "forecasts.csv" = forecast_lines(analyses),
        "accuracy.csv" = accuracy_lines(analyses),
        "cv.csv" = cv_lines(analyses),
        "correlogram.txt" = correlogram_lines(analyses),
        "chart.txt" = chart_lines(analyses),
        "plan.txt" = plan_lines(analyses)
    )
    for (name in names(outputs)) write_lines(name, outputs[[name]])
}
main()
