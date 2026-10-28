DIFFERENCE_KINDS <- c("none", "first", "seasonal", "both")
difference <- function(values, season, kind) {
    n <- length(values)
    if (kind == "none") return(list(values = values, offset = 0L))
    if (kind == "first") return(list(values = values[-1L] - values[-n], offset = 1L))
    if (kind == "seasonal") return(list(
        values = values[seq.int(season + 1L, n)] - values[seq_len(n - season)],
        offset = season
    ))
    times <- seq.int(season + 2L, n)
    list(
        values = (values[times] - values[times - 1L]) - (values[times - season] - values[times - season - 1L]),
        offset = season + 1L
    )
}
autocorrelation <- function(values, max_lag) {
    average <- series_mean(values)
    centered <- values - average
    n <- length(values)
    variance <- ordered_sum(centered * centered) / n
    correlations <- 1
    for (lag in seq_len(max_lag)) {
        times <- seq_len(n - lag)
        numerator <- ordered_sum(centered[times] * centered[times + lag])
        correlations <- c(correlations, numerator / n / variance)
    }
    list(mean = average, variance = variance, correlations = correlations)
}
durbin_levinson <- function(correlations) {
    coefficients <- list(numeric())
    partial <- 0
    variances <- 1
    for (order in seq_len(length(correlations) - 1L)) {
        previous <- tail(coefficients, 1L)[[1L]]
        indices <- seq_len(order - 1L)
        correction <- ordered_sum(previous[indices] * correlations[order - indices + 1L])
        theta <- (correlations[order + 1L] - correction) / tail(variances, 1L)
        current <- c(previous[indices] - theta * previous[order - indices], theta)
        coefficients <- c(coefficients, list(current))
        partial <- c(partial, theta)
        variances <- c(variances, tail(variances, 1L) * (1 - theta * theta))
    }
    list(coefficients = coefficients, partial = partial, variances = variances)
}
ar_residuals <- function(values, average, coefficients) {
    order <- length(coefficients)
    vapply(
        seq.int(order + 1L, length(values)),
        function(i) values[i] - average - ordered_sum(coefficients * (values[i - seq_len(order)] - average)),
        0
    )
}
ar_forecast <- function(values, differenced, offset, kind, average, coefficients, origin, steps, season) {
    transformed <- differenced[seq_len(origin - offset)]
    extended <- values[seq_len(origin)]
    result <- numeric(steps)
    for (step in seq_len(steps)) {
        predicted <- average + ordered_sum(coefficients * (transformed[length(transformed) - seq_along(coefficients) + 1L] - average))
        transformed <- c(transformed, predicted)
        n <- length(extended)
        if (kind == "first") predicted <- predicted + extended[n] else if (kind == "seasonal") predicted <- predicted + extended[n - season + 1L] else if (kind == "both") predicted <- predicted + extended[n] + extended[n - season + 1L] - extended[n - season]
        extended <- c(extended, predicted)
        result[step] <- predicted
    }
    result
}
ljung_box <- function(errors, lags) {
    n <- length(errors)
    correlations <- autocorrelation(errors, max(lags))$correlations
    lapply(lags, function(lag) {
        indices <- seq_len(lag)
        q <- n * (n + 2L) * ordered_sum(correlations[indices + 1L] * correlations[indices + 1L] / (n - indices))
        x <- q / 2
        term <- 1
        terms <- term
        for (i in seq_len(lag %/% 2L - 1L)) {
            term <- term * x / i
            terms <- c(terms, term)
        }
        list(lag = lag, q = q, p = exp(-x) * ordered_sum(terms))
    })
}
