off_diagonal <- function(matrix) {
  result <- 0
  for (p in seq_len(nrow(matrix)-1L)) for (q in seq.int(
      p+1L,
      nrow(matrix)
  )) result <- result+matrix[p,q]*matrix[p,q]
  result
}
jacobi <- function(matrix) {
  a <- matrix
  n <- nrow(matrix)
  v <- identity_matrix(n)
  initial <- off_diagonal(a)
  sweeps <- 0L
  if (initial > 0) for (number in seq_len(100L)) {
    for (p in seq_len(n-1L)) for (q in seq.int(p+1L,n)) {
      if (a[p,q] == 0) next
      theta <- (a[q,q]-a[p,p])/(2*a[p,q])
      t <- 1/(abs(theta)+sqrt(theta*theta+1))
      if (theta < 0) t <- -t
      c <- 1/sqrt(t*t+1)
      s <- t*c
      for (r in seq_len(n)) {
        if (r == p || r == q) next
        x <- a[r,p]
        y <- a[r,q]
        a[r,p] <- a[p,r] <- c*x-s*y
        a[r,q] <- a[q,r] <- s*x+c*y
      }
      value <- a[p,q]
      a[p,p] <- a[p,p]-t*value
      a[q,q] <- a[q,q]+t*value
      a[p,q] <- a[q,p] <- 0
      for (r in seq_len(n)) {
        x <- v[r,p]
        y <- v[r,q]
        v[r,p] <- c*x-s*y
        v[r,q] <- s*x+c*y
      }
    }
    remaining <- off_diagonal(a)
    if (sweeps == 0L && remaining < 1e-16*initial) sweeps <- number
    if (remaining < 1e-22*initial) break
  }
  order <- order(-diag(a),seq_len(n))
  list(values=diag(a)[order],vectors=lapply(order,function(k) orient(normalize(v[,k]))),sweeps=sweeps)
}
power_iteration <- function(matrix,references) {
  b <- matrix
  components <- list()
  for (reference in references) {
    x <- rep(1,length(reference))
    agreement <- NULL
    for (step in seq_len(1000L)) {
      x <- normalize(multiply(b,x))
      difference <- min(max_difference(x,reference),max_difference(x,-reference))
      if (is.null(agreement) && difference < 1e-6) agreement <- step
    }
    value <- dot_product(x,multiply(b,x))
    vector <- orient(normalize(x))
    b <- deflate(b,value,vector)
    components[[length(components)+1L]] <- list(value=value,vector=vector,agreement=agreement)
  }
  components
}
