ordered_sum <- function(values) {
  total <- 0
  for (value in values) total <- total+value
  total
}
determinant <- function(cov) cov[1L]*cov[3L]-cov[2L]*cov[2L]
mahalanobis <- function(point,mean,cov) {
  dx <- point[1L]-mean[1L]
  dy <- point[2L]-mean[2L]
  a <- cov[1L]
  b <- cov[2L]
  c <- cov[3L]
  (c*dx*dx-2*b*dx*dy+a*dy*dy)/determinant(cov)
}
weighted_log_density <- function(
    point,
    weight,
    mean,
    cov
) log(weight)-log(2*pi)-log(determinant(cov))/2-mahalanobis(point,mean,cov)/2
eigen_data <- function(cov) {
  a <- cov[1L]
  b <- cov[2L]
  c <- cov[3L]
  h <- (a+c)/2
  g <- sqrt(((a-c)/2)*((a-c)/2)+b*b)
  leading <- h+g
  trailing <- h-g
  if (b == 0) {
    direction <- if (a >= c) c(1,0) else c(0,1)
  } else {
    vector <- if (a >= c) c(leading-c,b) else c(b,leading-a)
    length <- sqrt(vector[1L]*vector[1L]+vector[2L]*vector[2L])
    direction <- if (vector[1L] < 0) -vector/length else vector/length
  }
  list(leading=leading,trailing=trailing,direction=direction,angle=atan2(direction[2L],direction[1L])*180/pi,
    axes=c(sqrt(leading),sqrt(trailing)),area=pi*sqrt(leading*trailing),correlation=b/sqrt(a*c))
}
bhattacharyya <- function(mean_a,cov_a,mean_b,cov_b) {
  average <- (cov_a+cov_b)/2
  distance <- mahalanobis(
      mean_b,
      mean_a,
      average
  )/8+log(determinant(average)/sqrt(determinant(cov_a)*determinant(cov_b)))/2
  list(distance=distance,coefficient=exp(-distance))
}
