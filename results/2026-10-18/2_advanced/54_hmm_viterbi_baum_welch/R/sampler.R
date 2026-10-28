minstd <- function(seed) {
  generator <- new.env(parent=emptyenv())
  generator$state <- as.numeric(seed)
  generator
}
uniform <- function(generator) {
  generator$state <- (48271*generator$state) %% 2147483647
  generator$state/2147483647
}
draw <- function(weights,generator) {
  total <- ordered_sum(weights)
  threshold <- uniform(generator)*total
  cumulative <- 0
  for (i in seq_along(weights)) {
    cumulative <- cumulative+weights[i]
    if (threshold < cumulative) return(i)
  }
  length(weights)
}
synthetic_sequence <- function(model,t_count,generator) {
  states <- observations <- integer(t_count)
  for (t in seq_len(t_count)) {
    weights <- if (t == 1L) model$initial else model$transition[states[t-1L],]
    state <- draw(weights,generator)
    symbol <- draw(model$emission[state,],generator)
    states[t] <- state
    observations[t] <- symbol
  }
  list(states=states,observations=observations)
}
posterior_path <- function(model,forward,generator) {
  t_count <- nrow(forward)
  k <- ncol(forward)
  path <- integer(t_count)
  path[t_count] <- draw(forward[t_count,],generator)
  if (t_count > 1L) for (t in seq.int(t_count-1L,1L)) {
    weights <- vapply(seq_len(k),function(i) forward[t,i]*model$transition[i,path[t+1L]],numeric(1))
    path[t] <- draw(weights,generator)
  }
  path
}
