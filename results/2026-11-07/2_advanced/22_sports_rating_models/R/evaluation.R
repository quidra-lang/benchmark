sigma <- function(value) 1 / (1 + exp(-value))
fit_link <- function(features, results, iterations) {
  alpha <- beta <- 0
  for (iteration in seq_len(iterations)) {
    g0 <- g1 <- h00 <- h01 <- h11 <- 0
    for (k in seq_along(features)) {
      z <- features[k]
      p <- sigma(alpha + beta * z)
      w <- p * (1 - p)
      g0 <- g0 + (results[k] - p)
      g1 <- g1 + (results[k] - p) * z
      h00 <- h00 + w
      h01 <- h01 + w * z
      h11 <- h11 + w * z * z
    }
    det <- h00 * h11 - h01 * h01
    next_alpha <- alpha + (h11 * g0 - h01 * g1) / det
    beta <- beta + (h00 * g1 - h01 * g0) / det
    alpha <- next_alpha
  }
  c(alpha, beta)
}
log_loss <- function(p, result2) {
  if (result2 == 2L) return(-log(p))
  if (result2 == 0L) return(-log(1 - p))
  -(log(p) / 2 + log(1 - p) / 2)
}
brier_score <- function(p, y) (p - y) * (p - y)
correctness2 <- function(p, result2) {
  if (result2 == 1L) return(1L)
  if (p > 0.5 && result2 == 2L || p < 0.5 && result2 == 0L) 2L else 0L
}
average_ranks2 <- function(values) vapply(values, function(value) {
  compared <- vapply(values, function(other) fraction_compare(other, value), numeric(1))
  2 * sum(compared > 0) + sum(compared == 0) + 1
}, numeric(1))
kendall_tau <- function(first, second) {
  count <- length(first)
  balance <- 0
  for (t in seq_len(count - 1L)) for (u in seq.int(t + 1L, count)) {
    agreement <- fraction_compare(first[[t]], first[[u]]) * fraction_compare(second[[t]], second[[u]])
    if (agreement > 0) balance <- balance + 1
    if (agreement < 0) balance <- balance - 1
  }
  fraction(balance, (count * (count - 1)) / 2)
}
spearman_rho <- function(first, second) {
  count <- length(first)
  a <- average_ranks2(first)
  b <- average_ranks2(second)
  squares <- 0
  for (i in seq_along(a)) {
    difference <- a[i] - b[i]
    squares <- squares + difference * difference
  }
  denominator <- 4 * count * (count * count - 1)
  fraction(denominator - 6 * squares, denominator)
}
