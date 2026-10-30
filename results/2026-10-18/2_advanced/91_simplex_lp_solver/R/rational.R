fraction <- function(numerator = 0, denominator = 1) {
  if (denominator < 0) {
    numerator <- -numerator
    denominator <- -denominator
  }
  a <- abs(numerator)
  b <- denominator
  while (b != 0) {
    remainder <- a %% b
    a <- b
    b <- remainder
  }
  structure(c(numerator / a, denominator / a), class = "fraction")
}
q_num <- function(value) unclass(value)[[1L]]
q_den <- function(value) unclass(value)[[2L]]
as_fraction <- function(value) if (inherits(value, "fraction")) value else fraction(value)
Ops.fraction <- function(e1, e2) {
  e1 <- as_fraction(e1)
  a <- q_num(e1)
  b <- q_den(e1)
  if (missing(e2)) return(if (.Generic == "-") fraction(-a, b) else e1)
  e2 <- as_fraction(e2)
  c <- q_num(e2)
  d <- q_den(e2)
  switch(.Generic,
         "+" = fraction(a * d + c * b, b * d),
         "-" = fraction(a * d - c * b, b * d),
         "*" = fraction(a * c, b * d),
         "/" = fraction(a * d, b * c),
         "==" = a * d == c * b,
         "!=" = a * d != c * b,
         "<" = a * d < c * b,
         ">" = a * d > c * b,
         "<=" = a * d <= c * b,
         ">=" = a * d >= c * b)
}
Math.fraction <- function(x, ...) {
  switch(.Generic, abs = fraction(abs(q_num(x)), q_den(x)),
         floor = q_num(x) %/% q_den(x),
         ceiling = -((-q_num(x)) %/% q_den(x)))
}
ZERO <- fraction()
qsum <- function(values) Reduce(`+`, values, init = ZERO)
qmin <- function(values) Reduce(function(a, b) if (a < b) a else b, values)
qmax <- function(values) Reduce(function(a, b) if (a > b) a else b, values)
fraction_text <- function(value) {
  numerator <- sprintf("%.0f", q_num(value))
  if (q_den(value) == 1) numerator else paste0(numerator, "/", sprintf("%.0f", q_den(value)))
}
shown <- function(value) if (is.null(value)) "-" else fraction_text(value)
endpoint <- function(value, lower) if (is.null(value)) if (lower) "-inf" else "inf" else fraction_text(value)
read_number <- function(word, signed = FALSE) {
  pattern <- if (signed) "^-?[0-9]+(\\.[0-9]+|/[0-9]+)?$" else "^[0-9]+(\\.[0-9]+|/[0-9]+)?$"
  if (!grepl(pattern, word)) return(NULL)
  if (grepl("/", word, fixed = TRUE)) {
    pair <- as.numeric(strsplit(word, "/", fixed = TRUE)[[1L]])
    if (pair[[2L]] == 0) return(NULL)
    return(fraction(pair[[1L]], pair[[2L]]))
  }
  if (grepl(".", word, fixed = TRUE)) {
    pair <- strsplit(word, ".", fixed = TRUE)[[1L]]
    sign <- if (startsWith(word, "-")) -1 else 1
    return(fraction(sign * as.numeric(gsub("[-.]", "", word)), 10 ^ nchar(pair[[2L]])))
  }
  fraction(as.numeric(word))
}
approximate <- function(value) {
  scaled <- floor(abs(value) * 1000000 + fraction(1, 2))
  sign <- if (value < 0 && scaled > 0) "-" else ""
  paste0(sign, sprintf("%.0f", scaled %/% 1000000), ".", sprintf("%06.0f", scaled %% 1000000))
}
