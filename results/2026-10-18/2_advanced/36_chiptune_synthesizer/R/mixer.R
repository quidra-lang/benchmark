new_buffer <- function(capacity, channels) new_object(
    count = 0L,
    samples = integer(capacity),
    lanes = matrix(0L, capacity, channels)
)
channel_value <- function(channel) {
  if (!channel$sounding) return(0L)
  level <- wave_value(channel$instrument, channel$mode, channel$phase, channel$register)
  channel$phase <- channel$phase + channel$increment
  if (channel$phase >= 65536) {
    channel$phase <- channel$phase - 65536L
    if (channel$instrument$wave == "NOISE") channel$register <- clock_register(channel$register, channel$mode)
  }
  (2L * level - 15L) * channel$amplitude
}
mix_tick <- function(channels, count, gain, muted, buffer) {
  clipped <- 0L
  samples <- buffer$samples
  lanes <- buffer$lanes
  for (i in seq_len(count)) {
    index <- buffer$count + i
    total <- 0
    for (k in seq_along(channels)) {
      value <- channel_value(channels[[k]])
      lanes[index, k] <- value
      if (!muted[[k]]) total <- total + value
    }
    sample <- 128L + (gain * total) %/% 4096
    if (sample < 0L || sample > 255L) {
      clipped <- clipped + 1L
      sample <- clamp(sample, 0L, 255L)
    }
    samples[[index]] <- as.integer(sample)
  }
  buffer$count <- buffer$count + count
  buffer$samples <- samples
  buffer$lanes <- lanes
  clipped
}
fade_out <- function(samples, fade) {
  total <- length(samples)
  count <- min(fade, total)
  for (index in seq.int(
      total - count + 1L,
      total
  )) samples[[index]] <- as.integer(128L + ((samples[[index]] - 128L) * (total - index)) %/% count)
  samples
}
