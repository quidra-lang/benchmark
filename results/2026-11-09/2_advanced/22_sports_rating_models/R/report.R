gcd <- function(a, b) {
  a <- abs(a)
  while (b != 0) {
    remainder <- a %% b
    a <- b
    b <- remainder
  }
  a
}
fraction <- function(p, q = 1) {
  if (q < 0) {
    p <- -p
    q <- -q
  }
  divisor <- gcd(p, q)
  unname(c(p / divisor, q / divisor))
}
fraction_add <- function(a, b) {
  common <- gcd(a[2L], b[2L])
  fraction(a[1L] * (b[2L] / common) + b[1L] * (a[2L] / common), (a[2L] / common) * b[2L])
}
fraction_multiply <- function(a, b) {
  x <- gcd(a[1L], b[2L])
  y <- gcd(b[1L], a[2L])
  fraction((a[1L] / x) * (b[1L] / y), (a[2L] / y) * (b[2L] / x))
}
fraction_divide <- function(a, value) fraction_multiply(a, fraction(1, value))
fraction_compare <- function(a, b) sign(a[1L] * b[2L] - b[1L] * a[2L])
fraction_real <- function(value) value[1L] / value[2L]
fraction_text <- function(value) paste0(sprintf("%.0f", value[1L]), "/", sprintf("%.0f", value[2L]))
fixed <- function(value, places = 4L) {
  text <- sprintf(paste0("%.", places, "f"), value)
  if (as.numeric(text) == 0 && startsWith(text, "-")) substring(text, 2L) else text
}
fixed_fraction <- function(value, places = 4L) {
  numerator <- abs(value[1L])
  whole <- numerator %/% value[2L]
  remainder <- numerator %% value[2L]
  digits <- 0
  scale <- 1
  for (i in seq_len(places)) {
    remainder <- remainder * 10
    digits <- digits * 10 + remainder %/% value[2L]
    remainder <- remainder %% value[2L]
    scale <- scale * 10
  }
  last <- if (places == 0L) whole else digits
  if (2 * remainder > value[2L] || 2 * remainder == value[2L] && last %% 2 != 0) {
    digits <- digits + 1
    if (digits == scale) {
      whole <- whole + 1
      digits <- 0
    }
  }
  sign_text <- if (value[1L] < 0 && (whole != 0 || digits != 0)) "-" else ""
  if (places == 0L) return(paste0(sign_text, sprintf("%.0f", whole)))
  paste0(sign_text, sprintf("%.0f", whole), ".", sprintf(paste0("%0", places, "d"), as.integer(digits)))
}
fraction_with_real <- function(value) paste(fraction_text(value), fixed_fraction(value))
decimal_value <- function(value, places) round(value * (10 ^ places))
write_lines <- function(name, lines) writeLines(lines, file.path("output", name), useBytes = TRUE)
