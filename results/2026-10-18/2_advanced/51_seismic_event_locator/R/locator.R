PI_VALUE <- 3.141592653589793
ordered_sum <- function(values) {
  total <- 0
  for (value in values) total <- total+value
  total
}
distance <- function(
    solution,
    station
) sqrt((solution[1L]-station$x)^2+(solution[2L]-station$y)^2+(solution[3L]+station$elevation)^2)
residuals <- function(solution,observations,velocity) vapply(
    observations,
    function(observation) observation$time-solution[4L]-distance(solution,observation$station)/velocity,
    numeric(1)
)
location_rms <- function(solution,observations,velocity) {
  errors <- residuals(solution,observations,velocity)
  sqrt(ordered_sum(errors*errors)/length(errors))
}
grid_search <- function(observations,params) {
  velocity <- params$velocity[1L]
  ranges <- lapply(
      params[c("grid_x","grid_y","grid_z")],
      function(values) seq(values[1L],values[2L],by=values[3L])
  )
  best <- numeric(4L)
  best_error <- Inf
  profile <- rep(Inf,length(ranges[[3L]]))
  for (x in ranges[[1L]]) for (y in ranges[[2L]]) for (zi in seq_along(ranges[[3L]])) {
    z <- ranges[[3L]][zi]
    solution <- c(x,y,z,0)
    deltas <- vapply(
        observations,
        function(observation) observation$time-distance(solution,observation$station)/velocity,
        numeric(1)
    )
    origin <- ordered_sum(deltas)/length(deltas)
    error <- ordered_sum((deltas-origin)*(deltas-origin))
    if (error < best_error) {
      best <- c(x,y,z,origin)
      best_error <- error
    }
    if (error < profile[zi]) profile[zi] <- error
  }
  list(solution=best,rms=sqrt(best_error/length(observations)),profile=sqrt(profile/length(observations)))
}
cholesky_lower <- function(matrix) {
  n <- nrow(matrix)
  lower <- matrix(0,n,n)
  for (a in seq_len(n)) for (c in seq_len(a)) {
    total <- ordered_sum(vapply(seq_len(c-1L),function(j) lower[a,j]*lower[c,j],numeric(1)))
    value <- matrix[a,c]-total
    lower[a,c] <- if (a == c) sqrt(value) else value/lower[c,c]
  }
  lower
}
cholesky_solve <- function(lower,right) {
  n <- length(right)
  forward <- solution <- numeric(n)
  for (a in seq_len(n)) {
    total <- ordered_sum(vapply(seq_len(a-1L),function(j) lower[a,j]*forward[j],numeric(1)))
    forward[a] <- (right[a]-total)/lower[a,a]
  }
  for (a in rev(seq_len(n))) {
    indices <- if (a < n) seq.int(a+1L,n) else integer()
    total <- ordered_sum(vapply(indices,function(j) lower[j,a]*solution[j],numeric(1)))
    solution[a] <- (forward[a]-total)/lower[a,a]
  }
  solution
}
normals <- function(solution,observations,velocity) {
  matrix <- matrix(0,4L,4L)
  right <- numeric(4L)
  errors <- residuals(solution,observations,velocity)
  for (i in seq_along(observations)) {
    station <- observations[[i]]$station
    d <- distance(solution,station)
    g <- c(
        (solution[1L]-station$x)/(velocity*d),
        (solution[2L]-station$y)/(velocity*d),
        (solution[3L]+station$elevation)/(velocity*d),
        1
    )
    for (a in seq_len(4L)) {
      right[a] <- right[a]+g[a]*errors[i]
      for (c in seq_len(4L)) matrix[a,c] <- matrix[a,c]+g[a]*g[c]
    }
  }
  list(matrix=matrix,right=right)
}
geiger <- function(initial,observations,velocity) {
  solution <- initial
  trace <- list()
  for (iteration in seq_len(8L)) {
    normal <- normals(solution,observations,velocity)
    delta <- cholesky_solve(cholesky_lower(normal$matrix),normal$right)
    for (a in seq_len(4L)) solution[a] <- solution[a]+delta[a]
    solution[3L] <- max(solution[3L],0)
    trace[[iteration]] <- list(
        number=iteration,
        solution=solution,
        rms=location_rms(solution,observations,velocity)
    )
  }
  list(
      solution=solution,
      trace=trace,
      residuals=residuals(solution,observations,velocity),
      rms=location_rms(solution,observations,velocity)
  )
}
run_location <- function(observations,params) {
  grid <- grid_search(observations,params)
  refined <- geiger(grid$solution,observations,params$velocity[1L])
  refined$grid <- grid
  refined
}
error_ellipse <- function(solution,observations,velocity) {
  normal <- normals(solution,observations,velocity)
  lower <- cholesky_lower(normal$matrix)
  inverse <- matrix(0,4L,4L)
  for (c in seq_len(4L)) inverse[,c] <- cholesky_solve(lower,as.numeric(seq_len(4L) == c))
  errors <- residuals(solution,observations,velocity)
  variance <- ordered_sum(errors*errors)/(length(observations)-4L)
  covariance <- variance*inverse
  xx <- covariance[1L,1L]
  yy <- covariance[2L,2L]
  xy <- covariance[1L,2L]
  midpoint <- (xx+yy)/2
  radius <- sqrt(((xx-yy)/2)^2+xy*xy)
  theta <- atan2(2*xy,xx-yy)/2*180/PI_VALUE
  azimuth <- 90-theta
  if (azimuth >= 180) azimuth <- azimuth-180
  list(
      smaj=sqrt(midpoint+radius),
      smin=sqrt(midpoint-radius),
      az=azimuth,
      erz=sqrt(covariance[3L,3L]),
      ert=sqrt(covariance[4L,4L])
  )
}
