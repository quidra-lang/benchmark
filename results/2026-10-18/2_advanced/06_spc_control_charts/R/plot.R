place <- function(band, position, symbol) {
  band[min(60, max(0, position)) + 1L] <- symbol
  band
}

framed_band <- function(center) {
  band <- rep(".", 61L)
  band[c(1L, 61L)] <- ":"
  place(band, center, "|")
}

limits_band <- function(limits, value, signalled) {
  span <- limits$ucl - limits$lcl
  band <- framed_band(floor(60 * ((limits$cl - limits$lcl) / span) + 0.5))
  band <- place(band, floor(60 * ((value - limits$lcl) / span) + 0.5), if (signalled) "*" else "o")
  paste(band, collapse = "")
}

cusum_band <- function(upper, lower, threshold, upper_signal, lower_signal) {
  band <- framed_band(30L)
  if (lower > 0) band <- place(band, 30 - min(30, floor(30 * (lower / threshold) + 0.5)), if (lower_signal) "*" else "-")
  if (upper > 0) band <- place(band, 30 + min(30, floor(30 * (upper / threshold) + 0.5)), if (upper_signal) "*" else "+")
  paste(band, collapse = "")
}

width_band <- function(scale, width, value, center, signalled) {
  band <- rep(".", 61L)
  edge <- min(30, floor(30 * (width / scale) + 0.5))
  band <- place(band, 30L, "|")
  band <- place(band, 30 - edge, ":")
  band <- place(band, 30 + edge, ":")
  band <- place(band, 30 + floor(30 * ((value - center) / scale) + 0.5), if (signalled) "*" else "o")
  paste(band, collapse = "")
}

standard_band <- function(z, ok) {
  band <- place(framed_band(30L), 30 + floor(10 * z + 0.5), if (ok) "o" else "*")
  paste(band, collapse = "")
}
