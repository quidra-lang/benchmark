ordered_sum <- function(values) {
    total <- 0
    for (value in values) total <- total + value
    total
}
score <- function(weights, vector) ordered_sum(weights * vector)
probability <- function(u) {
    if (u >= 0) return(1 / (1 + exp(-u)))
    e <- exp(u)
    e / (1 + e)
}
logistic_loss <- function(u, y) max(u, 0) - y * u + log(1 + exp(-abs(u)))
average_loss <- function(w, x, y) ordered_sum(vapply(
    seq_along(x),
    function(i) logistic_loss(score(w, x[[i]]), y[i]),
    0
)) / length(x)
penalty <- function(w) ordered_sum(w[-1L] * w[-1L])
objective <- function(w, x, y, lambda) average_loss(w, x, y) + lambda * penalty(w) / 2
gradient <- function(w, x, y, lambda) {
    totals <- numeric(length(w))
    for (i in seq_along(x)) {
        error <- probability(score(w, x[[i]])) - y[i]
        for (j in seq_along(w)) totals[j] <- totals[j] + error * x[[i]][j]
    }
    totals / length(x) + c(0, lambda * w[-1L])
}
hessian <- function(w, x, lambda) {
    size <- length(w)
    totals <- matrix(0, size, size)
    for (v in x) {
        pi <- probability(score(w, v))
        variance <- pi * (1 - pi)
        for (j in seq_len(size)) for (k in seq_len(j)) totals[j, k] <- totals[j, k] + variance * v[j] * v[k]
    }
    result <- matrix(0, size, size)
    for (j in seq_len(size)) for (k in seq_len(j)) {
        value <- totals[j, k] / length(x)
        if (j == k && j >= 2L) value <- value + lambda
        result[j, k] <- result[k, j] <- value
    }
    result
}
