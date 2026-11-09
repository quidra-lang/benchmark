maximum_index <- function(values) which.max(values)
emission_factors <- function(model,observation) if (observation == 0L) rep(
    1,
    length(model$states)
) else model$emission[,observation]
log_emission_factors <- function(model,observation) if (observation == 0L) rep(
    0,
    length(model$states)
) else log(model$emission[,observation])
scaled_forward <- function(model,observations) {
  k <- length(model$states)
  t_count <- length(observations)
  values <- emissions <- matrix(0,t_count,k)
  scales <- numeric(t_count)
  loglik <- 0
  for (t in seq_len(t_count)) {
    emissions[t,] <- emission_factors(model,observations[t])
    unscaled <- numeric(k)
    for (j in seq_len(k)) {
      incoming <- if (t == 1L) model$initial[j] else ordered_sum(vapply(
          seq_len(k),
          function(i) values[t-1L,i]*model$transition[i,j],
          numeric(1)
      ))
      unscaled[j] <- incoming*emissions[t,j]
    }
    scales[t] <- ordered_sum(unscaled)
    values[t,] <- unscaled/scales[t]
    loglik <- loglik+log(scales[t])
  }
  list(values=values,scales=scales,emissions=emissions,loglik=loglik)
}
forward_backward <- function(model,observations) {
  forward <- scaled_forward(model,observations)
  k <- length(model$states)
  t_count <- length(observations)
  backward <- matrix(0,t_count,k)
  backward[t_count,] <- 1
  if (t_count > 1L) for (t in seq.int(t_count-1L,1L)) for (i in seq_len(k))
    backward[t,i] <- ordered_sum(vapply(
        seq_len(k),
        function(j) model$transition[i,j]*forward$emissions[t+1L,j]*backward[t+1L,j],
        numeric(1)
    ))/forward$scales[t+1L]
  list(
      forward=forward$values,
      backward=backward,
      scales=forward$scales,
      emissions=forward$emissions,
      posterior=forward$values*backward,
      loglik=forward$loglik
  )
}
posterior_transition <- function(
    model,
    result,
    t,
    i,
    j
) result$forward[t,i]*model$transition[i,j]*result$emissions[t+1L,j]*result$backward[t+1L,j]/result$scales[t+1L]
viterbi <- function(model,observations) {
  k <- length(model$states)
  t_count <- length(observations)
  transition <- log(model$transition)
  scores <- log(model$initial)+log_emission_factors(model,observations[1L])
  previous <- matrix(0L,t_count,k)
  if (t_count > 1L) for (t in seq.int(2L,t_count)) {
    factors <- log_emission_factors(model,observations[t])
    next_scores <- numeric(k)
    for (j in seq_len(k)) {
      candidates <- scores+transition[,j]
      i <- maximum_index(candidates)
      previous[t,j] <- i
      next_scores[j] <- candidates[i]+factors[j]
    }
    scores <- next_scores
  }
  path <- integer(t_count)
  path[t_count] <- maximum_index(scores)
  logprob <- scores[path[t_count]]
  if (t_count > 1L) for (t in seq.int(t_count,2L)) path[t-1L] <- previous[t,path[t]]
  list(path=path,logprob=logprob)
}
decode <- function(model,observations) {
  fb <- forward_backward(model,observations)
  path <- viterbi(model,observations)
  posterior <- vapply(seq_len(length(observations)),function(t) maximum_index(fb$posterior[t,]),integer(1))
  confidence <- vapply(seq_along(posterior),function(t) fb$posterior[t,posterior[t]],numeric(1))
  list(viterbi=path$path,viterbi_logprob=path$logprob,posterior=posterior,confidence=confidence,fb=fb)
}
