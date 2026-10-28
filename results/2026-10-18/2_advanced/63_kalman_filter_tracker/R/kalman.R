transition_matrix <- function(model,t) {
  f <- identity_matrix(if (model == "CV") 4L else 6L)
  f[1L,3L] <- f[2L,4L] <- t
  if (model == "CA") {
    f[1L,5L] <- f[2L,6L] <- t*t/2
    f[3L,5L] <- f[4L,6L] <- t
  }
  f
}
process_noise <- function(model,t,q) {
  if (model == "CV") {
    entries <- list(c(1,1,q*t*t*t/3),c(1,3,q*t*t/2),c(3,3,q*t))
    result <- matrix(0,4L,4L)
  } else {
    entries <- list(
        c(1,1,q*t*t*t*t*t/20),
        c(1,3,q*t*t*t*t/8),
        c(1,5,q*t*t*t/6),
        c(3,3,q*t*t*t/3),
        c(3,5,q*t*t/2),
        c(5,5,q*t)
    )
    result <- matrix(0,6L,6L)
  }
  for (axis in 0:1) for (entry in entries) {
    row <- as.integer(entry[1L])+axis
    column <- as.integer(entry[2L])+axis
    result[row,column] <- result[column,row] <- entry[3L]
  }
  result
}
new_kalman <- function(model,q,sigma,velocity_variance,acceleration_variance,measurement) {
  n <- if (model == "CV") 4L else 6L
  variances <- c(sigma*sigma,sigma*sigma,velocity_variance,velocity_variance)
  if (n == 6L) variances <- c(variances,acceleration_variance,acceleration_variance)
  h <- matrix(0,2L,n)
  h[1L,1L] <- h[2L,2L] <- 1
  list2env(
      list(
          model=model,
          q=q,
          x=c(measurement,rep(0,n-2L)),
          p=diagonal_matrix(variances),
          h=h,
          r=diagonal_matrix(c(sigma*sigma,sigma*sigma)),
          f=NULL,
          xp=NULL,
          pp=NULL
      ),
      parent=emptyenv()
  )
}
predict_filter <- function(filter,interval) {
  filter$f <- transition_matrix(filter$model,interval)
  filter$x <- matrix_vector(filter$f,filter$x)
  filter$p <- matrix_product(
      matrix_product(filter$f,filter$p),
      t(filter$f)
  )+process_noise(filter$model,interval,filter$q)
  filter$xp <- filter$x
  filter$pp <- filter$p
}
innovation <- function(filter,measurement) {
  residual <- measurement-matrix_vector(filter$h,filter$x)
  covariance <- matrix_product(matrix_product(filter$h,filter$p),t(filter$h))+filter$r
  precision <- matrix_inverse(covariance)
  list(residual=residual,covariance=covariance,precision=precision,distance2=quadratic2(residual,precision))
}
update_filter <- function(filter,measurement,info=innovation(filter,measurement)) {
  gain <- matrix_product(matrix_product(filter$p,t(filter$h)),info$precision)
  correction <- identity_matrix(length(filter$x))-matrix_product(gain,filter$h)
  filter$x <- filter$x+matrix_vector(gain,info$residual)
  filter$p <- matrix_product(
      matrix_product(correction,filter$p),
      t(correction)
  )+matrix_product(matrix_product(gain,filter$r),t(gain))
  likelihood <- -log(2*pi)-log(determinant2(info$covariance))/2-info$distance2/2
  list(distance2=info$distance2,likelihood=likelihood,covariance=info$covariance)
}
filter_snapshot <- function(filter) list(x=filter$x,p=filter$p,xp=filter$xp,pp=filter$pp,f=filter$f)
smooth <- function(history) {
  states <- vector("list",length(history))
  states[[length(states)]] <- history[[length(history)]]$x
  if (length(history) > 1L) for (index in seq.int(length(history)-1L,1L)) {
    current <- history[[index]]
    following <- history[[index+1L]]
    gain <- matrix_product(matrix_product(current$p,t(following$f)),matrix_inverse(following$pp))
    states[[index]] <- current$x+matrix_vector(gain,states[[index+1L]]-following$xp)
  }
  states
}
