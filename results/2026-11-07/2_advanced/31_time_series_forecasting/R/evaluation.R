seasonal_scale <- function(values, season) {
    times <- seq.int(season + 1L, length(values))
    ordered_sum(abs(values[times] - values[times - season])) / (length(values) - season)
}
accuracy <- function(actual, predicted, scale) {
    n <- length(actual)
    errors <- actual - predicted
    mae <- ordered_sum(abs(errors)) / n
    list(me = ordered_sum(errors) / n, mae = mae, rmse = sqrt(ordered_sum(errors * errors) / n), mape = 100 * ordered_sum(abs(errors) / actual) / n,
         smape = 100 * ordered_sum(2 * abs(errors) / (abs(actual) + abs(predicted))) / n, mase = mae / scale)
}
winkler <- function(actual, low, high, multiplier) {
    if (actual < low) return(high - low + multiplier * (low - actual))
    if (actual > high) return(high - low + multiplier * (actual - high))
    high - low
}
rank_models <- function(names, metrics) names[order(
    vapply(names, function(name) metrics[[name]]$rmse, 0),
    seq_along(names)
)]
