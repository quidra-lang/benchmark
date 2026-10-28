ordered_sum <- function(values) {
  total <- 0
  for (value in values) total <- total+value
  total
}
make_stump <- function(feature,thresholds,values) list(feature=feature,thresholds=thresholds,values=values)
stump_output <- function(stump,values) stump$values[sum(values[stump$feature] > stump$thresholds)+1L]
search_space <- function(rows) {
  orders <- groups <- thresholds <- list()
  for (j in seq_along(rows[[1L]]$x)) {
    order <- order(vapply(rows,function(row) row$x[j],numeric(1)),seq_along(rows))
    batches <- list()
    distinct <- numeric()
    for (i in order) {
      value <- rows[[i]]$x[j]
      if (!length(distinct) || value != tail(distinct,1L)) {
        distinct <- c(distinct,value)
        batches[[length(batches)+1L]] <- integer()
      }
      batches[[length(batches)]] <- c(batches[[length(batches)]],i)
    }
    cuts <- c(distinct[1L]-1,(head(distinct,-1L)+tail(distinct,-1L))/2)
    orders[[j]] <- order
    groups[[j]] <- batches
    thresholds[[j]] <- cuts
  }
  list(rows=rows,orders=orders,groups=groups,thresholds=thresholds)
}
left_cumulative <- function(groups,values) {
  result <- 0
  total <- 0
  for (group in groups[-length(groups)]) {
    for (i in group) total <- total+values[i]
    result <- c(result,total)
  }
  result
}
choose_candidate <- function(candidates) {
  values <- vapply(candidates,`[[`,numeric(1),"error")
  candidates[[which(values <= min(values)+1e-9)[1L]]]
}
discrete_search <- function(space,labels,weights) {
  positive <- ifelse(labels == 1L,weights,0)
  negative <- ifelse(labels == -1L,weights,0)
  wp <- ordered_sum(positive)
  wn <- ordered_sum(negative)
  candidates <- list()
  for (j in seq_along(space$thresholds)) {
    lp <- left_cumulative(space$groups[[j]],positive)
    ln <- left_cumulative(space$groups[[j]],negative)
    for (k in seq_along(space$thresholds[[j]])) {
      threshold <- space$thresholds[[j]][k]
      candidates[[length(candidates)+1L]] <- list(
          error=lp[k]+(wn-ln[k]),
          feature=j,
          threshold=threshold,
          polarity=1L
      )
      candidates[[length(candidates)+1L]] <- list(
          error=ln[k]+(wp-lp[k]),
          feature=j,
          threshold=threshold,
          polarity=-1L
      )
    }
  }
  choose_candidate(candidates)
}
regression_search <- function(space,targets,weights) {
  w <- ordered_sum(weights)
  products <- weights*targets
  s <- ordered_sum(products)
  q <- ordered_sum(weights*targets*targets)
  candidates <- list()
  for (j in seq_along(space$thresholds)) {
    wl <- left_cumulative(space$groups[[j]],weights)
    sl <- left_cumulative(space$groups[[j]],products)
    for (k in seq_along(space$thresholds[[j]])) {
      wr <- w-wl[k]
      sr <- s-sl[k]
      right <- sr/wr
      left <- if (k == 1L) 0 else sl[k]/wl[k]
      gain <- if (k == 1L) sr*sr/wr else sl[k]*sl[k]/wl[k]+sr*sr/wr
      candidates[[length(candidates)+1L]] <- list(
          error=q-gain,
          feature=j,
          threshold=space$thresholds[[j]][k],
          left=left,
          right=right
      )
    }
  }
  best <- choose_candidate(candidates)
  list(stump=make_stump(best$feature,best$threshold,c(best$left,best$right)),error=best$error)
}
multiclass_search <- function(space,labels,weights,classes) {
  total_weight <- ordered_sum(weights)
  totals <- vapply(seq_len(classes),function(c) ordered_sum(weights[labels == c]),numeric(1))
  candidates <- list()
  for (j in seq_along(space$thresholds)) {
    left <- numeric(classes)
    for (k in seq_along(space$thresholds[[j]])) {
      if (k > 1L) for (i in space$groups[[j]][[k-1L]]) left[labels[i]] <- left[labels[i]]+weights[i]
      right <- totals-left
      a <- which.max(left)
      b <- which.max(right)
      candidates[[length(candidates)+1L]] <- list(
          error=total_weight-(left[a]+right[b]),
          feature=j,
          threshold=space$thresholds[[j]][k],
          left=a,
          right=b
      )
    }
  }
  best <- choose_candidate(candidates)
  list(stump=make_stump(best$feature,best$threshold,c(best$left,best$right)),error=best$error)
}
real_geometry <- function(space,bins) {
  n <- length(space$rows)
  cuts <- assignments <- list()
  for (j in seq_along(space$orders)) {
    values <- vapply(space$rows[space$orders[[j]]],function(row) row$x[j],numeric(1))
    ranks <- ((seq_len(bins-1L))*n) %/% bins
    feature_cuts <- (values[ranks]+values[ranks+1L])/2
    cuts[[j]] <- feature_cuts
    assignments[[j]] <- vapply(space$rows,function(row) sum(row$x[j] > feature_cuts)+1L,integer(1))
  }
  list(cuts=cuts,assignments=assignments)
}
real_search <- function(assignments,labels,weights,bins) {
  candidates <- lapply(seq_along(assignments),function(j) {
    positive <- negative <- numeric(bins)
    for (i in seq_along(labels)) {
      bin <- assignments[[j]][i]
      if (labels[i] == 1L) positive[bin] <- positive[bin]+weights[i] else negative[bin] <- negative[bin]+weights[i]
    }
    list(error=2*ordered_sum(sqrt(positive*negative)),feature=j,positive=positive,negative=negative)
  })
  choose_candidate(candidates)
}
