fir <- function(samples, divisor, taps) {
  output <- numeric(length(samples))
  clips <- 0L
  for (index in seq_along(samples)) {
    total <- 0
    for (tap in seq_len(min(length(taps), index))) total <- total + taps[tap] * samples[index - tap + 1L]
    value <- integer_divide(total, divisor)
    if (value < -32768 || value > 32767) clips <- clips + 1L
    output[index] <- sat(value)
  }
  list(samples = output, clipped = clips)
}

biquad <- function(samples, sections) {
  clips <- 0L
  for (section in sections) {
    output <- numeric(length(samples))
    u1 <- u2 <- v1 <- v2 <- 0
    for (index in seq_along(samples)) {
      input <- samples[index]
      total <- section[1L] * input + section[2L] * u1 + section[3L] * u2 - section[4L] * v1 - section[5L] * v2
      value <- integer_divide(total, 16384)
      if (value < -32768 || value > 32767) clips <- clips + 1L
      value <- sat(value)
      output[index] <- value
      u2 <- u1
      u1 <- input
      v2 <- v1
      v1 <- value
    }
    samples <- output
  }
  list(samples = samples, clipped = clips)
}

moving_average <- function(samples, width) {
  output <- numeric(length(samples))
  total <- 0
  for (index in seq_along(samples)) {
    total <- total + samples[index]
    if (index > width) total <- total - samples[index - width]
    output[index] <- rdiv(total, width)
  }
  output
}

dc_block <- function(samples, numerator, denominator) {
  output <- numeric(length(samples))
  previous_input <- previous_output <- 0
  clips <- 0L
  for (index in seq_along(samples)) {
    value <- samples[index] - previous_input + rdiv(numerator * previous_output, denominator)
    if (value < -32768 || value > 32767) clips <- clips + 1L
    previous_input <- samples[index]
    previous_output <- sat(value)
    output[index] <- previous_output
  }
  list(samples = output, clipped = clips)
}
