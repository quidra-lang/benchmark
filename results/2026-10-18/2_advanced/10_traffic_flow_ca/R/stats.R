integer_text <- function(value) sprintf("%.0f", value)
line_text <- function(...) paste(vapply(list(...), function(value) if (is.numeric(value)) integer_text(value) else value, character(1L)), collapse = " ")
integer_gcd <- function(a, b) {
  while (b) {
    remainder <- integer_mod(a, b)
    a <- b
    b <- remainder
  }
  a
}
dec <- function(numerator, denominator, places) {
  if (denominator == 0) return("-")
  scale <- 1
  for (index in seq_len(places)) scale <- scale * 10
  value <- integer_divide(2 * numerator * scale + denominator, 2 * denominator)
  paste0(integer_text(integer_divide(value, scale)), ".", sprintf(paste0("%0", places, ".0f"), integer_mod(value, scale)))
}
frac <- function(numerator, denominator) {
  if (denominator == 0) return("-")
  divisor <- integer_gcd(numerator, denominator)
  paste0(integer_text(integer_divide(numerator, divisor)), "/", integer_text(integer_divide(denominator, divisor)))
}
share_pair <- function(a, b) {
  divisor <- integer_gcd(a, b)
  c(integer_divide(a, divisor), integer_divide(b, divisor))
}
share_multiply <- function(a, b) {
  first <- integer_gcd(a[1L], b[2L])
  second <- integer_gcd(b[1L], a[2L])
  share_pair(integer_divide(a[1L], first) * integer_divide(b[1L], second), integer_divide(a[2L], second) * integer_divide(b[2L], first))
}
share_add <- function(a, b) {
  divisor <- integer_gcd(a[2L], b[2L])
  first <- integer_divide(b[2L], divisor)
  second <- integer_divide(a[2L], divisor)
  share_pair(a[1L] * first + b[1L] * second, a[2L] * first)
}
percentile <- function(times, q) times[integer_divide(q * length(times) + 99, 100)]
histogram_lines <- function(times, width) {
  first <- integer_divide(times[1L], width)
  bins <- seq.int(first, integer_divide(tail(times, 1L), width))
  counts <- vapply(bins, function(bin) sum(vapply(times, function(time) integer_divide(time, width) == bin, logical(1L))), integer(1L))
  top <- max(counts)
  vapply(seq_along(bins), function(index) {
    low <- bins[index] * width
    text <- line_text(" ", paste0(integer_text(low), "-", integer_text(low + width - 1L)), counts[index])
    stars <- integer_divide(80 * counts[index] + top, 2 * top)
    if (stars) paste(text, strrep("*", stars)) else text
  }, character(1L))
}
