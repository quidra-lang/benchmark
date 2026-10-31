initialize_optimizer <- function(count) {
  state <- new.env(parent=emptyenv())
  state$momentum <- state$first <- state$second <- numeric(count)
  state$power1 <- state$power2 <- 1
  state
}
epoch_rate <- function(run,epoch,step,gamma) {
  rate <- run$rate
  for (unused in seq_len((epoch-1L) %/% step)) rate <- rate*gamma
  rate
}
update_parameters <- function(theta,grad,state,run,rate) {
  if (run$optimizer == "SGD") for (i in seq_along(grad)) theta[i] <- theta[i]-rate*grad[i] else if (run$optimizer == "MOMENTUM") {
    mu <- run$extra[1L]
    for (i in seq_along(grad)) {
      state$momentum[i] <- mu*state$momentum[i]+grad[i]
      theta[i] <- theta[i]-rate*state$momentum[i]
    }
  } else {
    beta1 <- run$extra[1L]
    beta2 <- run$extra[2L]
    epsilon <- run$extra[3L]
    state$power1 <- state$power1*beta1
    state$power2 <- state$power2*beta2
    for (i in seq_along(grad)) {
      value <- grad[i]
      state$first[i] <- beta1*state$first[i]+(1-beta1)*value
      state$second[i] <- beta2*state$second[i]+(1-beta2)*value*value
      corrected_first <- state$first[i]/(1-state$power1)
      corrected_second <- state$second[i]/(1-state$power2)
      theta[i] <- theta[i]-rate*corrected_first/(sqrt(corrected_second)+epsilon)
    }
  }
  theta
}
