integer_sqrt <- function(value) {
  low <- 0
  high <- 1
  while (high * high <= value) high <- high * 2
  while (high - low > 1) {
    middle <- integer_divide(low + high, 2)
    if (middle * middle <= value) low <- middle else high <- middle
  }
  low
}

energy <- function(samples) sum(samples * samples)
rms <- function(samples) integer_sqrt(integer_divide(energy(samples), length(samples)))
zero_crossings <- function(samples) sum((head(samples, -1L) < 0) != (tail(samples, -1L) < 0))
count_clipped <- function(samples) sum(samples == 32767 | samples == -32768)
crest_fraction <- function(samples) {
  denominator <- energy(samples)
  if (denominator == 0) return("none")
  numerator <- peak(samples) * peak(samples) * length(samples)
  a <- numerator
  b <- denominator
  while (b) {
    remainder <- integer_mod(a, b)
    a <- b
    b <- remainder
  }
  paste0(integer_text(integer_divide(numerator, a)), "/", integer_text(integer_divide(denominator, a)))
}

autocorrelation <- function(samples, lag) sum(head(samples, length(samples) - lag) * tail(samples, length(samples) - lag))
pitch_lag <- function(samples, low, high) {
  best <- low
  value <- autocorrelation(samples, low)
  if (low < high) for (lag in seq.int(low + 1L, high)) {
    candidate <- autocorrelation(samples, lag)
    if (candidate > value) {
      best <- lag
      value <- candidate
    }
  }
  if (value > 0) best else NA_real_
}
