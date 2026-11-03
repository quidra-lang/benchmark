round_record <- function(
    stump,
    weights=numeric(),
    error=NULL,
    alpha=NULL,
    polarity=NULL,
    z=NULL,
    bound=NULL,
    loss=NULL
)
  list(stump=stump,weights=weights,error=error,alpha=alpha,polarity=polarity,z=z,bound=bound,loss=loss)
train_discrete <- function(rows,max_rounds,weights=NULL,shrinkage=1,space=NULL) {
  if (is.null(space)) space <- search_space(rows)
  labels <- vapply(rows,`[[`,integer(1),"label")
  if (is.null(weights)) weights <- rep(1/length(rows),length(rows))
  rounds <- list()
  bound <- 1
  stop <- "completed"
  for (unused in seq_len(max_rounds)) {
    best <- discrete_search(space,labels,weights)
    error <- best$error
    if (error >= 0.5) {
      stop <- "weak"
      break
    }
    alpha <- if (error <= 1e-10) 1 else shrinkage*(0.5*log((1-error)/error))
    stump <- make_stump(best$feature,best$threshold,c(-best$polarity*alpha,best$polarity*alpha))
    before <- weights
    for (i in seq_along(rows)) {
      row <- rows[[i]]
      decision <- if (row$x[best$feature] > best$threshold) best$polarity else -best$polarity
      factor <- if (decision == row$label) exp(-alpha) else exp(alpha)
      weights[i] <- if (weights[i] == 0) 0 else weights[i]*factor
    }
    normalizer <- ordered_sum(weights)
    weights <- weights/normalizer
    bound <- bound*normalizer
    rounds[[length(rounds)+1L]] <- round_record(
        stump,
        weights=before,
        error=error,
        alpha=alpha,
        polarity=best$polarity,
        z=normalizer,
        bound=bound
    )
    if (error <= 1e-10) {
      stop <- "perfect"
      break
    }
  }
  list(rounds=rounds,stop=stop,cuts=NULL)
}
train_samme <- function(rows,max_rounds,classes) {
  space <- search_space(rows)
  labels <- vapply(rows,`[[`,integer(1),"label")
  weights <- rep(1/length(rows),length(rows))
  rounds <- list()
  stop <- "completed"
  for (unused in seq_len(max_rounds)) {
    best <- multiclass_search(space,labels,weights,classes)
    stump <- best$stump
    error <- best$error
    if (error >= (classes-1L)/classes) {
      stop <- "weak"
      break
    }
    alpha <- if (error <= 1e-10) 1 else log((1-error)/error)+log(classes-1L)
    for (i in seq_along(rows)) if (stump_output(
        stump,
        rows[[i]]$x
    ) != rows[[i]]$label) weights[i] <- weights[i]*exp(alpha)
    weights <- weights/ordered_sum(weights)
    rounds[[length(rounds)+1L]] <- round_record(stump,error=error,alpha=alpha)
    if (error <= 1e-10) {
      stop <- "perfect"
      break
    }
  }
  list(rounds=rounds,stop=stop,cuts=NULL)
}
