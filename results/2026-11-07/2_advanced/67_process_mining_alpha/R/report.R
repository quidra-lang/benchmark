integer_gcd <- function(a,b) {
  while (b != 0) {
    remainder <- a %% b
    a <- b
    b <- remainder
  }
  a
}
q <- function(a,b=1) {
  divisor <- integer_gcd(abs(a),b)
  list(n=a %/% divisor,d=b %/% divisor)
}
qsub <- function(a,b) q(a$n*b$d-b$n*a$d,a$d*b$d)
qlt <- function(a,b) a$n*b$d < b$n*a$d
qge <- function(a,b) !qlt(a,b)
qmax <- function(a,b) if (qlt(a,b)) b else a
fraction <- function(value) {
  a <- abs(value$n)
  b <- value$d
  scaled <- (10000*a) %/% b
  sign <- if (value$n < 0) "-" else ""
  decimal_sign <- if (scaled == 0) "" else sign
  paste0(
      sign,
      sprintf("%.0f",a),
      "/",
      sprintf("%.0f",b),
      "=",
      decimal_sign,
      sprintf("%.0f",scaled %/% 10000),
      ".",
      sprintf("%04.0f",scaled %% 10000)
  )
}
percentage <- function(a,b) {
  scaled <- (10000*a) %/% b
  paste0(sprintf("%.0f",scaled %/% 100),".",sprintf("%02.0f",scaled %% 100),"%")
}
name_list <- function(values) if (length(values)) paste(values,collapse=",") else "-"
write_outputs <- function(outputs) {
  dir.create("output",showWarnings=FALSE)
  for (name in names(outputs)) writeLines(outputs[[name]],file.path("output",name),useBytes=TRUE)
}
