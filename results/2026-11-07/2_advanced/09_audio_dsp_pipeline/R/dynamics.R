envelope <- function(samples, attack, release) {
  levels <- numeric(length(samples))
  level <- 0
  for (index in seq_along(samples)) {
    magnitude <- min(abs(samples[index]), 32767)
    coefficient <- if (magnitude > level) attack else release
    level <- level + rdiv((magnitude - level) * coefficient, 32768)
    levels[index] <- level
  }
  levels
}

normalize <- function(samples, target) {
  source_peak <- peak(samples)
  list(samples = if (source_peak) rdiv(samples * target, source_peak) else samples, source_peak = source_peak)
}

gate <- function(samples, threshold, hold) {
  output <- numeric(length(samples))
  last_loud <- -hold - 1L
  muted <- 0L
  for (index in seq_along(samples)) {
    if (abs(samples[index]) >= threshold) last_loud <- index
    if (index - last_loud <= hold) output[index] <- samples[index] else muted <- muted + 1L
  }
  list(samples = output, muted = muted)
}

compress <- function(samples, threshold, ratio_num, ratio_den, attack, release) {
  levels <- envelope(samples, attack, release)
  output <- gains <- numeric(length(samples))
  gain <- 32768
  for (index in seq_along(samples)) {
    level <- levels[index]
    target <- if (level > threshold) rdiv((threshold + rdiv((level - threshold) * ratio_den, ratio_num)) * 32768, level) else 32768
    gain <- if (target < gain) target else gain + rdiv((target - gain) * release, 32768)
    gains[index] <- gain
    output[index] <- rdiv(samples[index] * gain, 32768)
  }
  list(samples = output, min_gain = min(gains), reduced = sum(gains < 32768))
}
