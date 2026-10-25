integer_divide <- function(a, b) {
  quotient <- floor(a / b)
  while (quotient * b > a) quotient <- quotient - 1
  while ((quotient + 1) * b <= a) quotient <- quotient + 1
  quotient
}
integer_mod <- function(a, b) a - integer_divide(a, b) * b
minstd <- function(seed) {
  generator <- new.env(parent = emptyenv())
  generator$state <- seed
  generator
}
draw <- function(generator) {
  generator$state <- integer_mod(48271 * generator$state, 2147483647)
  generator$state
}
select_weighted <- function(weights, value) {
  remainder <- integer_mod(value, sum(weights))
  total <- 0
  for (index in seq_along(weights)) {
    total <- total + weights[index]
    if (remainder < total) return(index)
  }
}
