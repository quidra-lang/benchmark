minstd <- function(seed) {
    rng <- new.env(parent = emptyenv())
    rng$state <- seed
    rng
}
draw <- function(rng) {
    value <- 48271L * (rng$state %% 44488L) - 3399L * (rng$state %/% 44488L)
    if (value <= 0L) value <- value + 2147483647L
    rng$state <- value
    value
}
shuffle_order <- function(order, rng) {
    if (length(order) > 1L) for (i in seq.int(length(order), 2L)) {
        k <- draw(rng) %% i + 1L
        order[c(i, k)] <- order[c(k, i)]
    }
    order
}
gradient_descent <- function(x, y, lambda, rate, iterations) {
    w <- numeric(length(x[[1L]]))
    checkpoints <- list(list(iteration = 0L, weights = w))
    for (t in seq_len(iterations)) {
        w <- w - rate * gradient(w, x, y, lambda)
        if (t %% 100L == 0L) checkpoints <- c(checkpoints, list(list(iteration = t, weights = w)))
    }
    checkpoints
}
stochastic_gradient_descent <- function(x, y, lambda, rate, batch_size, epochs, seed) {
    rng <- minstd(seed)
    order <- seq_along(x)
    w <- numeric(length(x[[1L]]))
    checkpoints <- list(list(iteration = 0L, weights = w))
    for (epoch in seq_len(epochs)) {
        order <- shuffle_order(order, rng)
        for (start in seq.int(1L, length(order), batch_size)) {
            batch <- order[seq.int(start, min(start + batch_size - 1L, length(order)))]
            w <- w - rate * gradient(w, x[batch], y[batch], lambda)
        }
        checkpoints <- c(checkpoints, list(list(iteration = epoch, weights = w)))
    }
    checkpoints
}
cholesky_lower <- function(matrix) {
    count <- nrow(matrix)
    lower <- matrix(0, count, count)
    for (j in seq_len(count)) for (i in seq.int(j, count)) {
        total <- 0
        for (k in seq_len(j - 1L)) total <- total + lower[i, k] * lower[j, k]
        remainder <- matrix[i, j] - total
        lower[i, j] <- if (i == j) sqrt(remainder) else remainder / lower[j, j]
    }
    lower
}
solve_lower <- function(lower, values) {
    count <- length(values)
    middle <- solution <- numeric(count)
    for (i in seq_len(count)) {
        total <- 0
        for (k in seq_len(i - 1L)) total <- total + lower[i, k] * middle[k]
        middle[i] <- (values[i] - total) / lower[i, i]
    }
    for (i in rev(seq_len(count))) {
        total <- 0
        if (i < count) for (k in seq.int(i + 1L, count)) total <- total + lower[k, i] * solution[k]
        solution[i] <- (middle[i] - total) / lower[i, i]
    }
    solution
}
newton_direction <- function(w, x, y, lambda) {
    g <- gradient(w, x, y, lambda)
    list(gradient = g, step = solve_lower(cholesky_lower(hessian(w, x, lambda)), g))
}
newton_method <- function(x, y, lambda) {
    w <- numeric(length(x[[1L]]))
    checkpoints <- list(list(iteration = 0L, weights = w))
    for (t in seq_len(10L)) {
        w <- w - newton_direction(w, x, y, lambda)$step
        checkpoints <- c(checkpoints, list(list(iteration = t, weights = w)))
    }
    checkpoints
}
