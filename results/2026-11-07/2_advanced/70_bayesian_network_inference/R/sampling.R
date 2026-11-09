new_minstd <- function(seed) {
  random <- new.env(parent=emptyenv())
  random$state <- seed
  random
}
uniform <- function(random) {
  random$state <- (48271*random$state) %% 2147483647
  random$state/2147483647
}
choose_state <- function(probabilities,random) {
  u <- uniform(random)
  cumulative <- 0
  for (state in seq_along(probabilities)) {
    cumulative <- cumulative+probabilities[state]
    if (u < cumulative) return(state)
  }
  length(probabilities)
}
weighted_sample <- function(topological,parents,cpts,sizes,evidence,random) {
  sample <- integer(length(sizes))
  weight <- 1
  for (v in topological) {
    row <- parent_row(parents[[v]],sample,sizes)
    observed <- match(v,evidence$variables)
    if (!is.na(observed)) {
      sample[v] <- evidence$states[observed]
      weight <- weight*cpts[[v]][row,sample[v]]
    } else sample[v] <- choose_state(cpts[[v]][row,],random)
  }
  list(sample=sample,weight=weight)
}
