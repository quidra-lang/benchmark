ordered_sum <- function(values) {
  result <- 0
  for (value in values) result <- result+value
  result
}
fit_ols <- function(matrix,response,weights,tolerance) {
  n <- nrow(matrix)
  p <- ncol(matrix)
  roots <- sqrt(weights)
  weighted <- matrix*roots
  lengths <- vapply(seq_len(p),function(j) sqrt(ordered_sum(weighted[,j]*weighted[,j])),numeric(1))
  work <- weighted
  transformed <- roots*response
  triangular <- matrix(0,p,p)
  accepted <- aliases <- integer()
  for (j in seq_len(p)) {
    k <- length(accepted)+1L
    indices <- seq.int(k,n)
    eta <- sqrt(ordered_sum(work[indices,j]*work[indices,j]))
    if (eta <= tolerance*lengths[j]) {
      aliases <- c(aliases,j)
      next
    }
    accepted <- c(accepted,j)
    alpha <- if (work[k,j] >= 0) -eta else eta
    vector <- work[indices,j]
    vector[1L] <- vector[1L]-alpha
    squared <- ordered_sum(vector*vector)
    previous <- seq_len(k-1L)
    triangular[previous,k] <- work[previous,j]
    triangular[k,k] <- alpha
    for (l in seq_len(p)[seq_len(p) > j]) {
      delta <- 2*ordered_sum(vector*work[indices,l])/squared
      work[indices,l] <- work[indices,l]-delta*vector
    }
    delta <- 2*ordered_sum(vector*transformed[indices])/squared
    transformed[indices] <- transformed[indices]-delta*vector
  }
  rank <- length(accepted)
  triangular <- triangular[seq_len(rank),seq_len(rank),drop=FALSE]
  effects <- transformed[seq_len(rank)]
  beta <- vector("list",p)
  for (k in rev(seq_len(rank))) {
    later <- seq_len(rank)[seq_len(rank) > k]
    tail <- ordered_sum(vapply(later,function(l) triangular[k,l]*beta[[accepted[l]]],numeric(1)))
    beta[[accepted[k]]] <- (effects[k]-tail)/triangular[k,k]
  }
  inverse <- matrix(0,rank,rank)
  for (m in seq_len(rank)) for (l in rev(seq_len(rank))) {
    later <- seq_len(rank)[seq_len(rank) > l]
    tail <- ordered_sum(triangular[l,later]*inverse[later,m])
    inverse[l,m] <- ((if (l == m) 1 else 0)-tail)/triangular[l,l]
  }
  variance <- vapply(seq_len(rank),function(k) ordered_sum(inverse[k,]*inverse[k,]),numeric(1))
  u <- g <- matrix(0,n,rank)
  leverage <- fitted <- numeric(n)
  for (i in seq_len(n)) {
    for (k in seq_len(rank)) u[i,k] <- ordered_sum(weighted[i,accepted]*inverse[,k])
    leverage[i] <- ordered_sum(u[i,]*u[i,])
    for (k in seq_len(rank)) g[i,k] <- ordered_sum(inverse[k,]*u[i,])
    fitted[i] <- ordered_sum(vapply(
        seq_len(rank),
        function(k) matrix[i,accepted[k]]*beta[[accepted[k]]],
        numeric(1)
    ))
  }
  residual <- response-fitted
  eps <- roots*residual
  rss <- ordered_sum(eps*eps)
  list(matrix=matrix,response=response,weights=weights,n=n,p=p,accepted=accepted,aliases=aliases,rank=rank,
    triangular=triangular,effects=effects,beta=beta,inverse=inverse,variance=variance,u=u,g=g,
    leverage=leverage,fitted=fitted,residual=residual,eps=eps,rss=rss)
}
