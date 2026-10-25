integer_divide <- function(a, b) {
  if (b < 0) {
    a <- -a
    b <- -b
  }
  quotient <- floor(a / b)
  while (quotient * b > a) quotient <- quotient - 1
  while ((quotient + 1) * b <= a) quotient <- quotient + 1
  quotient
}

rdiv <- function(a, b) vapply(a, function(value) integer_divide(2 * value + b, 2 * b), numeric(1L))
integer_mod <- function(a, b) a - b * integer_divide(a, b)
sat <- function(value) pmax(-32768, pmin(32767, value))
clipped_result <- function(values) list(samples = sat(values), clipped = sum(values < -32768 | values > 32767))
peak <- function(samples) max(abs(samples))
signal_record <- function(name, rate, samples, origin = "input", ingredients = list()) list(name = name, rate = rate, samples = samples, origin = origin, ingredients = ingredients)
integer_text <- function(value) sprintf("%.0f", value)

read_signals <- function() {
  lines <- readLines("input/signals.txt", warn = FALSE)
  signals <- list()
  index <- 1L
  while (index <= length(lines)) {
    fields <- strsplit(lines[index], " ", fixed = TRUE)[[1L]]
    count <- as.numeric(fields[4L])
    index <- index + 1L
    samples <- numeric()
    while (length(samples) < count) {
      samples <- c(samples, as.numeric(strsplit(lines[index], " ", fixed = TRUE)[[1L]]))
      index <- index + 1L
    }
    signals[[length(signals) + 1L]] <- signal_record(fields[2L], as.numeric(fields[3L]), samples)
  }
  signals
}

format_signal <- function(signal) {
  lines <- paste("SIGNAL", signal$name, integer_text(signal$rate), length(signal$samples))
  for (first in seq.int(1L, length(signal$samples), by = 16L)) lines <- c(lines, paste(integer_text(signal$samples[seq.int(first, min(first + 15L, length(signal$samples)))]), collapse = " "))
  lines
}

impulse <- function(count, position, amplitude) {
  samples <- rep(0, count)
  samples[position + 1L] <- amplitude
  samples
}
step_signal <- function(count, position, amplitude) c(rep(0, position), rep(amplitude, count - position))
noise <- function(count, seed) {
  samples <- numeric(count)
  state <- seed
  for (index in seq_len(count)) {
    state <- integer_mod(48271 * state, 2147483647)
    samples[index] <- integer_mod(state, 65536) - 32768
  }
  samples
}
