hex_lines <- function(samples) {
  vapply(
      seq.int(1L, length(samples), by = 32L),
      function(start) paste(
          sprintf("%02X", samples[seq.int(start, min(start + 31L, length(samples)))]),
          collapse = ""
      ),
      ""
  )
}
adler32_text <- function(values) {
  a <- 1
  b <- 0
  for (value in values) {
    a <- (a + value) %% 65521
    b <- (b + a) %% 65521
  }
  paste0(sprintf("%04X", as.integer(b)), sprintf("%04X", as.integer(a)))
}
integer_sqrt <- function(value) {
  low <- 0
  high <- value + 1
  while (low + 1 < high) {
    middle <- (low + high) %/% 2
    if (middle == 0 || middle <= value %/% middle) low <- middle else high <- middle
  }
  low
}
peak <- function(values, center) if (length(values)) max(abs(as.numeric(values) - center)) else 0
root_mean_square <- function(values, center) {
  centered <- as.numeric(values) - center
  integer_sqrt(sum(centered * centered) %/% length(values))
}
zero_crossings <- function(samples) sum((head(samples, -1L) < 128L) != (tail(samples, -1L) < 128L))
