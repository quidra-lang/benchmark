shifted_scores <- function(weights, vector) {
    scores <- vapply(weights, function(row) score(row, vector), 0)
    scores - max(scores)
}
softmax_probabilities <- function(weights, vector) {
    shifted <- shifted_scores(weights, vector)
    total <- ordered_sum(exp(shifted))
    exp(shifted) / total
}
predicted_class <- function(probabilities) which.max(probabilities) - 1L
softmax_loss <- function(weights, vector, label) {
    shifted <- shifted_scores(weights, vector)
    log(ordered_sum(exp(shifted))) - shifted[label + 1L]
}
softmax_average_loss <- function(w, x, labels) ordered_sum(vapply(
    seq_along(x),
    function(i) softmax_loss(w, x[[i]], labels[i]),
    0
)) / length(x)
softmax_objective <- function(
    w,
    x,
    labels,
    lambda
) softmax_average_loss(w, x, labels) + lambda * ordered_sum(unlist(
    lapply(w, function(row) row[-1L] * row[-1L]),
    use.names = FALSE
)) / 2
softmax_gradient <- function(w, x, labels, lambda) {
    totals <- lapply(w, function(row) numeric(length(row)))
    for (i in seq_along(x)) {
        probabilities <- softmax_probabilities(w, x[[i]])
        for (k in seq_along(w)) {
            error <- probabilities[k] - as.numeric(labels[i] == k - 1L)
            for (j in seq_along(w[[k]])) totals[[k]][j] <- totals[[k]][j] + error * x[[i]][j]
        }
    }
    lapply(seq_along(w), function(k) totals[[k]] / length(x) + c(0, lambda * w[[k]][-1L]))
}
softmax_train <- function(x, labels, classes, lambda, rate, iterations) {
    w <- lapply(seq_len(classes), function(k) numeric(length(x[[1L]])))
    checkpoints <- list(list(iteration = 0L, weights = w))
    for (t in seq_len(iterations)) {
        direction <- softmax_gradient(w, x, labels, lambda)
        w <- lapply(seq_along(w), function(k) w[[k]] - rate * direction[[k]])
        if (t %% 100L == 0L) checkpoints <- c(checkpoints, list(list(iteration = t, weights = w)))
    }
    checkpoints
}
