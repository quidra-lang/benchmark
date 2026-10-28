S <- 4096
floor_div <- function(a,b) a %/% b
mul <- function(a,b) (a*b) %/% S
integer_sqrt <- function(n) {
  low <- 0
  high <- 1
  while (high*high <= n) high <- high*2
  while (high-low > 1) {
    middle <- (low+high) %/% 2
    if (middle*middle <= n) low <- middle else high <- middle
  }
  low
}
