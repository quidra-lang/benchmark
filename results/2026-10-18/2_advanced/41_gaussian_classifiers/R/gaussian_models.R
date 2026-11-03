MODEL_NAMES <- c("NB","LDA","QDA")
train_model <- function(rows,features,class_count,name,prior_mode,epsilon,gamma) {
  p <- length(features)
  n <- length(rows)
  groups <- lapply(
      seq_len(class_count),
      function(k) lapply(Filter(function(r) r$y == k,rows),function(r) r$x[features])
  )
  counts <- lengths(groups)
  means <- lapply(groups,function(group) vapply(seq_len(p),function(j) ordered_sum(vapply(group,`[`,numeric(1),j))/length(group),numeric(1)))
  scatter <- lapply(seq_len(class_count),function(k) {
    result <- matrix(0,p,p)
    for (a in seq_len(p)) for (b in seq_len(p)) result[a,b] <- ordered_sum(vapply(groups[[k]],
      function(x) (x[a]-means[[k]][a])*(x[b]-means[[k]][b]),numeric(1)))
    result
  })
  center <- vapply(
      seq_len(p),
      function(j) ordered_sum(vapply(rows,function(r) r$x[features[j]],numeric(1)))/n,
      numeric(1)
  )
  variances <- vapply(
      seq_len(p),
      function(j) ordered_sum(vapply(rows,function(r) (r$x[features[j]]-center[j])^2,numeric(1)))/n,
      numeric(1)
  )
  priors <- if (prior_mode == "empirical") counts/n else rep(1/class_count,class_count)
  pooled <- matrix(0,p,p)
  for (a in seq_len(p)) for (b in seq_len(p)) pooled[a,b] <- ordered_sum(vapply(
      scatter,
      function(s) s[a,b],
      numeric(1)
  ))/(n-class_count)
  max_variance <- max(variances)
  added <- epsilon*max_variance
  covariance <- lapply(seq_len(class_count),function(k) {
    matrix <- matrix(0,p,p)
    for (a in seq_len(p)) for (b in seq_len(p)) matrix[a,b] <- if (name == "LDA") pooled[a,b] else
      if (name == "NB") { if (a == b) scatter[[k]][a,b]/counts[k]+added else 0 } else
      scatter[[k]][a,b]/(counts[k]-1)*(if (a == b) 1 else 1-gamma)
    matrix
  })
  factors <- lapply(covariance,cholesky_factor)
  determinants <- vapply(factors,log_determinant,numeric(1))
  list(name=name,features=features,counts=counts,means=means,scatter=scatter,center=center,variances=variances,
    priors=priors,pooled=pooled,max_variance=max_variance,added=added,covariance=covariance,
    factors=factors,determinants=determinants,epsilon=epsilon,gamma=gamma)
}
distances_vector <- function(model,vector) vapply(seq_along(model$means),
  function(k) quadratic_form(model$factors[[k]],vector-model$means[[k]]),numeric(1))
distances <- function(model,values) distances_vector(model,values[model$features])
infer_vector <- function(model,vector,costs=NULL) {
  q <- distances_vector(model,vector)
  normalizer <- length(vector)*log(2*pi)/2
  scores <- vapply(
      seq_along(q),
      function(k) log(model$priors[k])-normalizer-model$determinants[k]/2-q[k]/2,
      numeric(1)
  )
  predicted <- which.max(scores)
  maximum <- scores[predicted]
  exponentials <- exp(scores-maximum)
  total <- ordered_sum(exponentials)
  posterior <- exponentials/total
  log_posterior <- (scores-maximum)-log(total)
  decision <- if (is.null(costs)) predicted else which.min(vapply(seq_along(q),
    function(b) ordered_sum(posterior*costs[,b]),numeric(1)))
  list(
      predicted=predicted,
      posterior=posterior,
      log_posterior=log_posterior,
      confidence=max(posterior),
      decision=decision
  )
}
infer <- function(model,values,costs=NULL) infer_vector(model,values[model$features],costs)
predict_class <- function(model,values) infer(model,values)$predicted
