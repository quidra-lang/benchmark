ordered_sum <- function(values) {
    result <- 0
    for (value in values) result <- result + value
    result
}
series_mean <- function(values) ordered_sum(values) / length(values)
sample_variance <- function(values) {
    average <- series_mean(values)
    ordered_sum((values - average) * (values - average)) / (length(values) - 1L)
}
decompose <- function(values, season) {
    n <- length(values)
    half <- season %/% 2L
    defined <- seq.int(half + 1L, n - half)
    trend <- rep(NA_real_, n)
    for (t in defined) {
        value <- 0.5 * values[t - half]
        for (i in seq.int(t - half + 1L, t + half - 1L)) value <- value + values[i]
        value <- value + 0.5 * values[t + half]
        trend[t] <- value / season
    }
    additive <- multiplicative <- numeric(season)
    for (position in seq.int(0L, season - 1L)) {
        times <- defined[(defined - 1L) %% season == position]
        additive[position + 1L] <- series_mean(values[times] - trend[times])
        multiplicative[position + 1L] <- series_mean(values[times] / trend[times])
    }
    additive <- additive - ordered_sum(additive) / season
    multiplicative <- multiplicative / (ordered_sum(multiplicative) / season)
    residual_add <- residual_mult <- rep(NA_real_, n)
    for (t in defined) {
        j <- (t - 1L) %% season + 1L
        residual_add[t] <- values[t] - trend[t] - additive[j]
        residual_mult[t] <- values[t] / (trend[t] * multiplicative[j])
    }
    list(
        trend = trend,
        additive = additive,
        multiplicative = multiplicative,
        residual_add = residual_add,
        residual_mult = residual_mult,
        defined = defined
    )
}
least_squares_line <- function(values) {
    n <- length(values)
    center <- (n + 1L) / 2
    average <- series_mean(values)
    numerator <- ordered_sum((seq_len(n) - center) * (values - average))
    denominator <- ordered_sum((seq_len(n) - center) * (seq_len(n) - center))
    slope <- numerator / denominator
    c(intercept = average - slope * center, slope = slope)
}
