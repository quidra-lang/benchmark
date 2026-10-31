point_xy <- function(point) c(point$x,point$y)
covariance_type_adjust <- function(initial,type) {
  weights <- initial$weights
  means <- initial$means
  source <- initial$covariances
  if (type == "FULL") {
    covariances <- source
  } else if (type == "DIAG") {
    covariances <- lapply(source,function(cov) c(cov[1L],0,cov[3L]))
  } else if (type == "SPHERICAL") {
    covariances <- lapply(source,function(cov) c((cov[1L]+cov[3L])/2,0,(cov[1L]+cov[3L])/2))
  } else {
    shared <- vapply(
        seq_len(3L),
        function(j) ordered_sum(vapply(seq_along(weights),function(k) weights[k]*source[[k]][j],numeric(1))),
        numeric(1)
    )
    covariances <- replicate(length(weights),shared,simplify=FALSE)
  }
  list(weights=weights,means=means,covariances=covariances,type=type)
}
responsibilities <- function(points,model) {
  records <- list()
  loglik <- 0
  for (point in points) {
    scores <- vapply(
        seq_along(model$weights),
        function(k) weighted_log_density(
            point_xy(point),
            model$weights[k],
            model$means[[k]],
            model$covariances[[k]]
        ),
        numeric(1)
    )
    maximum <- max(scores)
    exponentials <- exp(scores-maximum)
    normalizer <- ordered_sum(exponentials)
    normalized <- exponentials/normalizer
    log_density <- maximum+log(normalizer)
    records[[length(records)+1L]] <- list(responsibilities=normalized,log_density=log_density,scores=scores)
    loglik <- loglik+log_density
  }
  list(records=records,loglik=loglik)
}
update_model <- function(points,records,type,epsilon) {
  n <- length(points)
  k_count <- length(records[[1L]]$responsibilities)
  counts <- vapply(
      seq_len(k_count),
      function(k) ordered_sum(vapply(records,function(row) row$responsibilities[k],numeric(1))),
      numeric(1)
  )
  weights <- counts/n
  means <- lapply(seq_len(k_count),function(k) c(
    ordered_sum(vapply(
        seq_len(n),
        function(i) records[[i]]$responsibilities[k]*points[[i]]$x,
        numeric(1)
    ))/counts[k],
    ordered_sum(vapply(
        seq_len(n),
        function(i) records[[i]]$responsibilities[k]*points[[i]]$y,
        numeric(1)
    ))/counts[k]))
  scatter <- lapply(seq_len(k_count),function(k) {
    a <- b <- c <- 0
    for (i in seq_len(n)) {
      r <- records[[i]]$responsibilities[k]
      dx <- points[[i]]$x-means[[k]][1L]
      dy <- points[[i]]$y-means[[k]][2L]
      a <- a+r*dx*dx
      b <- b+r*dx*dy
      c <- c+r*dy*dy
    }
    c(a,b,c)
  })
  if (type == "TIED") {
    shared <- vapply(seq_len(3L),function(j) ordered_sum(vapply(scatter,`[`,numeric(1),j))/n+if (j == 2L) 0 else epsilon,numeric(1))
    covariances <- replicate(k_count,shared,simplify=FALSE)
  } else covariances <- lapply(seq_len(k_count),function(k) {
    a <- scatter[[k]][1L]
    b <- scatter[[k]][2L]
    c <- scatter[[k]][3L]
    nk <- counts[k]
    if (type == "FULL") return(c(a/nk+epsilon,b/nk,c/nk+epsilon))
    if (type == "DIAG") return(c(a/nk+epsilon,0,c/nk+epsilon))
    variance <- (a/nk+c/nk)/2+epsilon
    c(variance,0,variance)
  })
  list(weights=weights,means=means,covariances=covariances,type=type)
}
run_em <- function(points,initial,type,iterations,epsilon) {
  model <- covariance_type_adjust(initial,type)
  step <- responsibilities(points,model)
  trace <- step$loglik
  for (unused in seq_len(iterations)) {
    model <- update_model(points,step$records,type,epsilon)
    step <- responsibilities(points,model)
    trace <- c(trace,step$loglik)
  }
  list(model=model,records=step$records,trace=trace,loglik=step$loglik)
}
