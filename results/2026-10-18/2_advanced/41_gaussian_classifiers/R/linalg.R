ordered_sum <- function(values) {
  total <- 0
  for (value in values) total <- total+value
  total
}
dot_product <- function(a,b) ordered_sum(a*b)
cholesky_factor <- function(matrix) {
  n <- nrow(matrix)
  lower <- matrix(0,n,n)
  for (i in seq_len(n)) for (j in seq_len(i)) {
    k <- seq_len(j-1L)
    value <- matrix[i,j]-ordered_sum(lower[i,k]*lower[j,k])
    lower[i,j] <- if (i == j) sqrt(value) else value/lower[j,j]
  }
  lower
}
forward <- function(lower,right) {
  n <- length(right)
  result <- numeric(n)
  for (i in seq_len(n)) {
    k <- seq_len(i-1L)
    result[i] <- (right[i]-ordered_sum(lower[i,k]*result[k]))/lower[i,i]
  }
  result
}
backward <- function(lower,right) {
  n <- length(right)
  result <- numeric(n)
  for (i in rev(seq_len(n))) {
    k <- seq_len(n)[seq_len(n) > i]
    result[i] <- (right[i]-ordered_sum(lower[k,i]*result[k]))/lower[i,i]
  }
  result
}
log_determinant <- function(lower) 2*ordered_sum(log(diag(lower)))
quadratic_form <- function(lower,difference) {
  transformed <- forward(lower,difference)
  dot_product(transformed,transformed)
}
jacobi <- function(matrix) {
  n <- nrow(matrix)
  current <- matrix
  vectors <- diag(n)
  sweeps <- 0L
  repeat {
    squares <- numeric()
    for (a in seq_len(n-1L)) for (b in seq.int(a+1L,n)) squares <- c(squares,current[a,b]^2)
    if (sqrt(ordered_sum(squares)) < 1e-12 || sweeps == 50L) break
    for (a in seq_len(n-1L)) for (b in seq.int(a+1L,n)) {
      if (current[a,b] == 0) next
      theta <- (current[b,b]-current[a,a])/(2*current[a,b])
      sg <- if (theta >= 0) 1 else -1
      t <- sg/(abs(theta)+sqrt(theta*theta+1))
      co <- 1/sqrt(t*t+1)
      si <- t*co
      for (k in seq_len(n)) {
        if (k == a || k == b) next
        x <- current[k,a]
        y <- current[k,b]
        current[k,a] <- current[a,k] <- co*x-si*y
        current[k,b] <- current[b,k] <- si*x+co*y
      }
      w <- current[a,b]
      current[a,a] <- current[a,a]-t*w
      current[b,b] <- current[b,b]+t*w
      current[a,b] <- current[b,a] <- 0
      for (k in seq_len(n)) {
        x <- vectors[k,a]
        y <- vectors[k,b]
        vectors[k,a] <- co*x-si*y
        vectors[k,b] <- si*x+co*y
      }
    }
    sweeps <- sweeps+1L
  }
  list(values=diag(current),vectors=vectors,sweeps=sweeps)
}
