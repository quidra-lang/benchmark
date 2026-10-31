euclid <- function(a, b) {
  while (b != 0) {
    remainder <- a %% b
    a <- b
    b <- remainder
  }
  a
}

pairs <- list(c(48, 180), c(1071, 462), c(7, 91), c(13, 97), c(36288, 98280))
for (pair in pairs) {
  a <- pair[1]
  b <- pair[2]
  divisor <- euclid(a, b)
  multiple <- (a %/% divisor) * b
  cat(sprintf("gcd(%d, %d) = %d, lcm(%d, %d) = %d\n", a, b, divisor, a, b, multiple))
}
