update_weights <- function(rows,weights,stump) {
  updated <- vapply(
      seq_along(rows),
      function(i) weights[i]*exp(-rows[[i]]$label*stump_output(stump,rows[[i]]$x)),
      numeric(1)
  )
  updated/ordered_sum(updated)
}
train_real <- function(rows,max_rounds,bins,smoothing,convergence) {
  space <- search_space(rows)
  geometry <- real_geometry(space,bins)
  labels <- vapply(rows,`[[`,integer(1),"label")
  weights <- rep(1/length(rows),length(rows))
  rounds <- list()
  bound <- 1
  stop <- "completed"
  for (unused in seq_len(max_rounds)) {
    best <- real_search(geometry$assignments,labels,weights,bins)
    normalizer <- best$error
    if (normalizer >= 1-convergence) {
      stop <- "converged"
      break
    }
    values <- 0.5*log((best$positive+smoothing)/(best$negative+smoothing))
    stump <- make_stump(best$feature,geometry$cuts[[best$feature]],values)
    bound <- bound*normalizer
    rounds[[length(rounds)+1L]] <- round_record(stump,weights=weights,z=normalizer,bound=bound)
    weights <- update_weights(rows,weights,stump)
  }
  list(rounds=rounds,stop=stop,cuts=geometry$cuts)
}
train_gentle <- function(rows,max_rounds) {
  space <- search_space(rows)
  targets <- vapply(rows,`[[`,integer(1),"label")
  weights <- rep(1/length(rows),length(rows))
  rounds <- list()
  for (unused in seq_len(max_rounds)) {
    best <- regression_search(space,targets,weights)
    rounds[[length(rounds)+1L]] <- round_record(best$stump,weights=weights,error=best$error)
    weights <- update_weights(rows,weights,best$stump)
  }
  list(rounds=rounds,stop="completed",cuts=NULL)
}
train_logit <- function(rows,max_rounds,clip_limit) {
  space <- search_space(rows)
  targets <- vapply(rows,function(row) as.numeric(row$label == 1L),numeric(1))
  scores <- numeric(length(rows))
  probabilities <- rep(0.5,length(rows))
  rounds <- list()
  for (unused in seq_len(max_rounds)) {
    q <- probabilities*(1-probabilities)
    responses <- pmax(-clip_limit,pmin(clip_limit,(targets-probabilities)/q))
    weights <- q/ordered_sum(q)
    best <- regression_search(space,responses,weights)
    stump <- make_stump(best$stump$feature,best$stump$thresholds,best$stump$values/2)
    for (i in seq_along(rows)) {
      scores[i] <- scores[i]+stump_output(stump,rows[[i]]$x)
      probabilities[i] <- 1/(1+exp(-2*scores[i]))
    }
    loss <- ordered_sum(vapply(
        seq_along(rows),
        function(i) log(1+exp(-2*rows[[i]]$label*scores[i])),
        numeric(1)
    ))/length(rows)
    rounds[[length(rounds)+1L]] <- round_record(stump,weights=weights,error=best$error,loss=loss)
  }
  list(rounds=rounds,stop="completed",cuts=NULL)
}
