new_rng <- function(seed) {
  rng <- new.env(parent = emptyenv())
  rng$state <- as.numeric(seed)
  rng
}

rng_draw <- function(rng) {
  rng$state <- (48271 * rng$state) %% 2147483647
  rng$state
}
rng_rnd <- function(rng, n) rng_draw(rng) %% n
rng_roll <- function(rng, count, sides) {
  total <- 0
  for (i in seq_len(count)) total <- total + 1 + rng_rnd(rng, sides)
  total
}
rng_select <- function(rng, weights) {
  q <- rng_rnd(rng, sum(weights))
  cumulative <- 0
  for (i in seq_along(weights)) {
    cumulative <- cumulative + weights[i]
    if (q < cumulative) return(i)
  }
  stop("Empty weights")
}
