rk4_step <- function(rates,state,multiplier) {
  h <- 0.25
  half <- h/2
  sixth <- h/6
  k1 <- rates(state,multiplier)
  k2 <- rates(state+half*k1,multiplier)
  k3 <- rates(state+half*k2,multiplier)
  k4 <- rates(state+h*k3,multiplier)
  state+sixth*(((k1+2*k2)+2*k3)+k4)
}
simulate <- function(rates,initial,multipliers,inflows) {
  state <- as.numeric(initial)
  daily <- list()
  for (multiplier in multipliers) {
    state[inflows] <- 0
    for (unused in seq_len(4L)) state <- rk4_step(rates,state,multiplier)
    daily[[length(daily)+1L]] <- state
  }
  daily
}
