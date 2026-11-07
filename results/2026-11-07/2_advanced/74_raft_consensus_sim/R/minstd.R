new_minstd <- function(seed) {
  random <- new.env(parent=emptyenv())
  random$state <- seed
  random$draws <- 0L
  random
}
draw_random <- function(random) {
  value <- 48271L*(random$state %% 44488L)-3399L*(random$state %/% 44488L)
  if (value <= 0L) value <- value+2147483647L
  random$state <- value
  random$draws <- random$draws+1L
  value
}
between <- function(random,minimum,maximum) minimum+draw_random(random) %% (maximum-minimum+1L)
