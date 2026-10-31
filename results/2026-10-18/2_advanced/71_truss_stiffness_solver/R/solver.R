factor_cholesky <- function(matrix,free) {
  n <- nrow(matrix)
  lower <- matrix(0,n,n)
  for (i in seq_len(n)) for (j in seq_len(i)) {
    w <- matrix[i,j]
    for (h in seq_len(j-1L)) w <- w-lower[i,h]*lower[j,h]
    if (j < i) lower[i,j] <- w/lower[j,j] else {
      if (w <= 1e-9*matrix[i,i]) return(list(lower=NULL,unstable=free[i]))
      lower[i,i] <- sqrt(w)
    }
  }
  list(lower=lower,unstable=0L)
}
solve_cholesky <- function(lower,right) {
  n <- length(right)
  intermediate <- result <- numeric(n)
  for (i in seq_len(n)) {
    w <- right[i]
    for (h in seq_len(i-1L)) w <- w-lower[i,h]*intermediate[h]
    intermediate[i] <- w/lower[i,i]
  }
  for (i in rev(seq_len(n))) {
    w <- intermediate[i]
    if (i < n) for (h in seq.int(i+1L,n)) w <- w-lower[h,i]*result[h]
    result[i] <- w/lower[i,i]
  }
  result
}
