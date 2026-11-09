fixed <- function(value, places = 4L) {
    text <- sprintf(paste0("%.", places, "f"), value)
    if (startsWith(text, "-") && as.numeric(text) == 0) substring(text, 2L) else text
}
ratio <- function(a, b) {
    if (b == 0L) return("-")
    q <- (20000 * a + b) %/% (2 * b)
    paste0(sprintf("%.0f", q %/% 10000), ".", sprintf("%04d", as.integer(q %% 10000)))
}
gcd <- function(a, b) {
    while (b != 0L) {
        remainder <- a %% b
        a <- b
        b <- remainder
    }
    a
}
fraction <- function(a, b = NULL) {
    if (is.null(b)) {
        b <- a[2L]
        a <- a[1L]
    }
    divisor <- gcd(a, b)
    paste0(a %/% divisor, "/", b %/% divisor, " ", ratio(a, b))
}
confusion <- function(predictions, targets) list(
    tp = sum(predictions == 1L & targets == 1L),
    fp = sum(predictions == 1L & targets == 0L),
    tn = sum(predictions == 0L & targets == 0L),
    fn = sum(predictions == 0L & targets == 1L)
)
auc <- function(scores, targets) {
    order <- order(scores, seq_along(scores))
    positives <- sum(targets)
    rank_sum <- 0L
    start <- 1L
    while (start <= length(order)) {
        end <- start
        while (end < length(order) && scores[order[end + 1L]] == scores[order[start]]) end <- end + 1L
        for (position in seq.int(
            start,
            end
        )) if (targets[order[position]] == 1L) rank_sum <- rank_sum + start + end
        start <- end + 1L
    }
    c(rank_sum - positives * (positives + 1L), 2L * positives * (length(targets) - positives))
}
roc_points <- function(probabilities, targets) {
    order <- order(-probabilities, seq_along(probabilities))
    points <- list()
    tp <- fp <- 0L
    for (position in seq_along(order)) {
        i <- order[position]
        if (targets[i] == 1L) tp <- tp + 1L else fp <- fp + 1L
        if (position == length(order) || probabilities[order[position + 1L]] != probabilities[i]) points <- c(
            points,
            list(list(threshold = probabilities[i], tp = tp, fp = fp))
        )
    }
    points
}
