smoothed_model <- function(template,name,initial,transition,emission,alpha) make_model(
    name,
    template$states,
    template$symbols,
    template$missing,
    initial+alpha,
    transition+alpha,
    emission+alpha
)
baum_welch_step <- function(model,sequences,pseudocount) {
  k <- length(model$states)
  m <- length(model$symbols)
  initial <- numeric(k)
  transition <- matrix(0,k,k)
  emission <- matrix(0,k,m)
  for (observations in sequences) {
    result <- forward_backward(model,observations)
    for (i in seq_len(k)) initial[i] <- initial[i]+result$posterior[1L,i]
    for (t in seq_along(observations)) for (i in seq_len(k)) {
      observation <- observations[t]
      if (observation != 0L) emission[i,observation] <- emission[i,observation]+result$posterior[t,i]
      if (t < length(observations)) for (j in seq_len(k)) transition[i,j] <- transition[i,j]+posterior_transition(
          model,
          result,
          t,
          i,
          j
      )
    }
  }
  smoothed_model(model,"BAUM_WELCH",initial,transition,emission,pseudocount)
}
estimate_by_counting <- function(template,pairs,alpha,name="SUPERVISED") {
  k <- length(template$states)
  m <- length(template$symbols)
  initial <- numeric(k)
  transition <- matrix(0,k,k)
  emission <- matrix(0,k,m)
  for (pair in pairs) {
    observations <- pair$observations
    path <- pair$path
    initial[path[1L]] <- initial[path[1L]]+1
    for (t in seq_along(path)) {
      state <- path[t]
      if (observations[t] != 0L) emission[state,observations[t]] <- emission[state,observations[t]]+1
      if (t < length(path)) transition[state,path[t+1L]] <- transition[state,path[t+1L]]+1
    }
  }
  smoothed_model(template,name,initial,transition,emission,alpha)
}
total_loglik <- function(model,sequences) ordered_sum(vapply(
    sequences,
    function(observations) scaled_forward(model,observations)$loglik,
    numeric(1)
))
