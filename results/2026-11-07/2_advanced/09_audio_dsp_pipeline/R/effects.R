gain <- function(samples, numerator, denominator) clipped_result(rdiv(samples * numerator, denominator))

mix <- function(tracks, weights, denominator) {
  count <- max(lengths(tracks))
  output <- numeric(count)
  clips <- 0L
  for (index in seq_len(count)) {
    total <- 0
    for (track in seq_along(tracks)) if (index <= length(tracks[[track]])) total <- total + weights[track] * tracks[[track]][index]
    value <- rdiv(total, denominator)
    if (value < -32768 || value > 32767) clips <- clips + 1L
    output[index] <- sat(value)
  }
  list(samples = output, clipped = clips)
}

delay_signal <- function(samples, count) c(rep(0, count), samples)
echo <- function(samples, delay, numerator, denominator, tail) {
  output <- c(samples, rep(0, tail))
  clips <- 0L
  if (delay < length(output)) for (index in seq.int(delay + 1L, length(output))) {
    value <- output[index] + rdiv(numerator * output[index - delay], denominator)
    if (value < -32768 || value > 32767) clips <- clips + 1L
    output[index] <- sat(value)
  }
  list(samples = output, clipped = clips)
}

resampled_length <- function(length, old_rate, new_rate) integer_divide((length - 1L) * new_rate, old_rate) + 1L
resample <- function(samples, old_rate, new_rate) {
  output <- numeric(resampled_length(length(samples), old_rate, new_rate))
  for (index in seq_along(output)) {
    position <- integer_divide((index - 1L) * old_rate, new_rate)
    remainder <- (index - 1L) * old_rate - position * new_rate
    output[index] <- samples[position + 1L]
    if (remainder > 0) output[index] <- output[index] + rdiv((samples[position + 2L] - samples[position + 1L]) * remainder, new_rate)
  }
  output
}

fade <- function(samples, fade_in, fade_out) {
  output <- samples
  for (index in seq_len(fade_in)) output[index] <- rdiv(output[index] * (index - 1L), fade_in)
  if (fade_out > 0L) for (index in seq.int(length(output) - fade_out + 1L, length(output))) output[index] <- rdiv(output[index] * (length(output) - index), fade_out)
  output
}
