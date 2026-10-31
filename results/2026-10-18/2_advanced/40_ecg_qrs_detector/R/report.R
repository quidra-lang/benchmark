rdiv <- function(a,b) (2*a+b) %/% (2*b)
integer_text <- function(value) sprintf("%.0f",value)
two <- function(value) {
  paste0(if (value < 0) "-" else "",integer_text(abs(value) %/% 100),
         ".",sprintf("%02.0f",abs(value) %% 100))
}
four <- function(value) paste0(integer_text(value %/% 10000),".",sprintf("%04.0f",value %% 10000))
fraction <- function(a,b) {
  x <- abs(a)
  y <- abs(b)
  while (y != 0) {
    remainder <- x %% y
    x <- y
    y <- remainder
  }
  paste0(integer_text(a %/% x),"/",integer_text(b %/% x))
}
ratio <- function(a,b) {
  if (b == 0) return(paste0(integer_text(a),"/0 none"))
  paste0(integer_text(a),"/",integer_text(b)," reduced=",fraction(a,b),
         " percent=",two(rdiv(10000*a,b)))
}
missing_dash <- function(value) if (is.null(value)) "-" else integer_text(value)
maybe_two <- function(value) if (is.null(value)) "none" else two(value)
