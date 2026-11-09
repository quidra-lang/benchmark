correlation <- function(xs, ys) {
  mx <- sequential_sum(xs) / length(xs)
  my <- sequential_sum(ys) / length(ys)
  xy <- xx <- yy <- 0
  for (i in seq_along(xs)) {
    dx <- xs[i] - mx
    dy <- ys[i] - my
    xy <- xy + dx * dy
    xx <- xx + dx * dx
    yy <- yy + dy * dy
  }
  xy / sqrt(xx * yy)
}
contingency_table <- function(first, second, rows, columns) {
  table <- matrix(0, rows, columns)
  for (i in seq_along(first)) table[first[i], second[i]] <- table[first[i], second[i]] + 1
  table
}
new_fraction <- function(p, q) list(p = p, q = q)
ari_value <- function(ari) ari$p / ari$q
ari_greater <- function(first, second) first$p * second$q > second$p * first$q
pair_count <- function(value) (value * (value - 1)) %/% 2
adjusted_rand_index <- function(table) {
  count <- same <- row_pairs <- column_pairs <- 0
  columns <- numeric(ncol(table))
  for (a in seq_len(nrow(table))) {
    total <- 0
    for (b in seq_len(ncol(table))) {
      value <- table[a, b]
      total <- total + value
      same <- same + pair_count(value)
      columns[b] <- columns[b] + value
    }
    count <- count + total
    row_pairs <- row_pairs + pair_count(total)
  }
  for (total in columns) column_pairs <- column_pairs + pair_count(total)
  total <- pair_count(count)
  p <- 2 * (total * same - row_pairs * column_pairs)
  q <- total * (row_pairs + column_pairs) - 2 * row_pairs * column_pairs
  if (q == 0) return(new_fraction(1, 1))
  if (q < 0) {
    p <- -p
    q <- -q
  }
  first <- abs(p)
  second <- q
  while (second != 0) {
    remainder <- first %% second
    first <- second
    second <- remainder
  }
  new_fraction(p %/% first, q %/% first)
}
silhouette_values <- function(partition, groups, delta) {
  sizes <- tabulate(partition, nbins = groups)
  values <- numeric(length(partition))
  for (i in seq_along(partition)) {
    own <- partition[i]
    if (sizes[own] == 1) next
    sums <- numeric(groups)
    for (j in seq_along(partition)) if (j != i) sums[partition[j]] <- sums[partition[j]] + delta[i, j]
    inner <- sums[own] / (sizes[own] - 1)
    outer <- Inf
    for (g in seq_len(groups)) if (g != own) outer <- min(outer, sums[g] / sizes[g])
    values[i] <- (outer - inner) / max(inner, outer)
  }
  values
}
