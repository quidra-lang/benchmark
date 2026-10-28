new_imm <- function(densities,transition,initial,sigma,velocity_variance,measurement) {
  models <- lapply(densities,function(q) new_kalman("CV",q,sigma,velocity_variance,0,measurement))
  list2env(
      list(models=models,transition=matrix(transition,2L,2L,byrow=TRUE),probabilities=initial),
      parent=emptyenv()
  )
}
imm_step <- function(filter,interval,measurement) {
  mu <- filter$probabilities
  transition <- filter$transition
  predicted <- vapply(1:2,function(j) transition[1L,j]*mu[1L]+transition[2L,j]*mu[2L],numeric(1))
  old_states <- lapply(filter$models,function(m) m$x)
  old_covariances <- lapply(filter$models,function(m) m$p)
  likelihoods <- numeric(2L)
  for (j in 1:2) {
    model <- filter$models[[j]]
    w1 <- transition[1L,j]*mu[1L]/predicted[j]
    w2 <- transition[2L,j]*mu[2L]/predicted[j]
    mixed <- w1*old_states[[1L]]+w2*old_states[[2L]]
    covariance <- matrix(0,4L,4L)
    for (r in 1:4) for (s in 1:4) covariance[r,s] <- w1*(old_covariances[[1L]][r,s]+(old_states[[1L]][r]-mixed[r])*(old_states[[1L]][s]-mixed[s]))+w2*(old_covariances[[2L]][
        r,
        s
    ]+(old_states[[2L]][r]-mixed[r])*(old_states[[2L]][s]-mixed[s]))
    model$x <- mixed
    model$p <- covariance
    predict_filter(model,interval)
    likelihood <- 1
    if (!is.null(measurement)) {
      update <- update_filter(model,measurement)
      likelihood <- exp(-update$distance2/2)/(2*pi*sqrt(determinant2(update$covariance)))
    }
    likelihoods[j] <- likelihood
  }
  denominator <- likelihoods[1L]*predicted[1L]+likelihoods[2L]*predicted[2L]
  filter$probabilities <- likelihoods*predicted/denominator
}
imm_estimate <- function(filter) filter$probabilities[1L]*filter$models[[1L]]$x+filter$probabilities[2L]*filter$models[[2L]]$x
