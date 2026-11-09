Z95 <- 1.959963984540054
total <- function(values) {
  result <- 0
  for (value in values) result <- result+value
  result
}
solve_system <- function(matrix,vector) {
  a <- matrix
  b <- vector
  n <- length(b)
  for (k in seq_len(n)) for (i in seq_len(n)[seq_len(n) > k]) {
    factor <- a[i,k]/a[k,k]
    for (j in seq.int(k,n)) a[i,j] <- a[i,j]-factor*a[k,j]
    b[i] <- b[i]-factor*b[k]
  }
  result <- numeric(n)
  for (i in rev(seq_len(n))) {
    value <- b[i]
    for (j in seq_len(n)[seq_len(n) > i]) value <- value-a[i,j]*result[j]
    result[i] <- value/a[i,i]
  }
  result
}
inverse_matrix <- function(matrix) {
  n <- nrow(matrix)
  result <- matrix(0,n,n)
  for (column in seq_len(n)) {
    unit <- numeric(n)
    unit[column] <- 1
    result[,column] <- solve_system(matrix,unit)
  }
  result
}
log_gamma <- function(a) {
  coefficients <- c(76.18009172947146,-86.50532032941677,24.01409824083091,
    -1.231739572450155,0.001208650973866179,-0.000005395239384953)
  xi <- a+5.5
  xi <- xi-(a+0.5)*log(xi)
  sigma <- 1.000000000190015
  y <- a
  for (coefficient in coefficients) {
    y <- y+1
    sigma <- sigma+coefficient/y
  }
  -xi+log(2.5066282746310005*sigma/a)
}
gamma_q <- function(a,x) {
  if (x == 0) return(1)
  prefactor <- exp(-x+a*log(x)-log_gamma(a))
  if (x < a+1) {
    alpha <- a
    term <- 1/a
    sigma <- term
    for (unused in seq_len(1000L)) {
      alpha <- alpha+1
      term <- term*(x/alpha)
      sigma <- sigma+term
      if (abs(term) < abs(sigma)*1e-15) break
    }
    return(1-sigma*prefactor)
  }
  epsilon <- 1e-300
  b <- x+1-a
  c <- 1/epsilon
  d <- 1/b
  h <- d
  for (i in seq_len(1000L)) {
    an <- -i*(i-a)
    b <- b+2
    d <- an*d+b
    if (abs(d) < epsilon) d <- epsilon
    c <- b+an/c
    if (abs(c) < epsilon) c <- epsilon
    d <- 1/d
    delta <- d*c
    h <- h*delta
    if (abs(delta-1) < 1e-15) break
  }
  prefactor*h
}
chi_square_p <- function(statistic,degrees) gamma_q(degrees/2,statistic/2)
