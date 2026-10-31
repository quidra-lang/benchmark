sequential_sum <- function(values) {
  total <- 0
  for (value in values) total <- total + value
  total
}

ordered_values <- function(values) sort(values, method = "radix")
mean_value <- function(values) sum(values) / (100 * length(values))

doubled_median <- function(values) {
  ordered <- ordered_values(values)
  count <- length(ordered)
  ordered[(count + 1L) %/% 2L] + ordered[count %/% 2L + 1L]
}

median_value <- function(values) doubled_median(values) / 200

trimmed_mean <- function(values) {
  ordered <- ordered_values(values)
  count <- length(ordered)
  trim <- count %/% 10L
  sum(ordered[seq.int(trim + 1L, count - trim)]) / (100 * (count - 2L * trim))
}

sd_value <- function(values) {
  center <- mean_value(values)
  squares <- 0
  for (value in values) {
    deviation <- value / 100 - center
    squares <- squares + deviation * deviation
  }
  sqrt(squares / (length(values) - 1L))
}

central_moments <- function(values) {
  center <- mean_value(values)
  second <- third <- fourth <- 0
  for (value in values) {
    e <- value / 100 - center
    second <- second + e * e
    third <- third + e * e * e
    fourth <- fourth + e * e * e * e
  }
  c(second, third, fourth) / length(values)
}

mad_value <- function(values) doubled_median(abs(2 * values - doubled_median(values))) / 400

quantile_numerator <- function(values, percent) {
  ordered <- ordered_values(values)
  position <- (length(values) - 1L) * percent
  index <- position %/% 100 + 1L
  fraction <- position %% 100
  100 * ordered[index] + if (fraction == 0) 0 else fraction * (ordered[index + 1L] - ordered[index])
}

winsorized <- function(values) {
  ordered <- ordered_values(values)
  trim <- length(values) %/% 10L
  pmin(pmax(values, ordered[trim + 1L]), ordered[length(values) - trim])
}

mean_difference <- function(x, y) (length(y) * sum(x) - length(x) * sum(y)) / (100 * length(x) * length(y))
median_ratio <- function(x, y) doubled_median(x) / doubled_median(y)
hodges_lehmann <- function(x, y) doubled_median(unlist(lapply(x, function(first) first - y), use.names = FALSE)) / 200

pooled_sd <- function(x, y) {
  first <- sd_value(x)
  second <- sd_value(y)
  squares <- (length(x) - 1L) * first * first + (length(y) - 1L) * second * second
  sqrt(squares / (length(x) + length(y) - 2L))
}

cohen_d <- function(x, y) mean_difference(x, y) / pooled_sd(x, y)

correlation_value <- function(x, y) {
  first_center <- mean_value(x)
  second_center <- mean_value(y)
  products <- first_squares <- second_squares <- 0
  for (index in seq_along(x)) {
    e <- x[index] / 100 - first_center
    f <- y[index] / 100 - second_center
    products <- products + e * f
    first_squares <- first_squares + e * e
    second_squares <- second_squares + f * f
  }
  products / sqrt(first_squares * second_squares)
}

resample_indices <- function(generator, size) {
  vapply(seq_len(size), function(index) generator$below(size) + 1L, numeric(1L))
}

ordinary_indices <- function(generator, size, count) {
  lapply(seq_len(count), function(index) resample_indices(generator, size))
}

balanced_indices <- function(generator, size, count) {
  sequence <- generator$shuffle(rep(seq_len(size), count))
  lapply(seq_len(count), function(index) sequence[seq.int((index - 1L) * size + 1L, index * size)])
}

without <- function(values, index) values[-index]

mean_and_se <- function(values) {
  average <- sequential_sum(values) / length(values)
  squares <- 0
  for (value in values) {
    difference <- value - average
    squares <- squares + difference * difference
  }
  c(average, sqrt(squares / (length(values) - 1L)))
}

phi <- function(x) {
  if (x < 0) return(1 - phi(-x))
  eta <- 1 / (1 + 0.2316419 * x)
  psi <- eta * (0.319381530 + eta * (-0.356563782 + eta * (1.781477937 + eta * (-1.821255978 + eta * 1.330274429))))
  1 - 0.3989422804014327 * exp(-(x * x) / 2) * psi
}

phi_inverse <- function(p) {
  if (p > 0.5) return(-phi_inverse(1 - p))
  eta <- sqrt(-2 * log(p))
  numerator <- 2.515517 + eta * (0.802853 + eta * 0.010328)
  denominator <- 1 + eta * (1.432788 + eta * (0.189269 + eta * 0.001308))
  -(eta - numerator / denominator)
}
