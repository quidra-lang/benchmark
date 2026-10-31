TIDE_PI <- 3.141592653589793
angle <- function(speed,time) {
  degrees <- speed*time
  reduced <- degrees-360*floor(degrees/360)
  reduced*TIDE_PI/180
}
regressors <- function(time,selected) {
  vector <- 1
  for (constituent in selected) {
    theta <- tide_angle(constituent$speed,time)
    vector <- c(vector,cos(theta),sin(theta))
  }
  vector
}
solve_with_inverse <- function(matrix,right) {
  n <- length(right)
  augmented <- cbind(matrix,right,diag(1,n))
  for (column in seq_len(n)) {
    pivot <- column-1L+which.max(abs(augmented[seq.int(column,n),column]))
    if (pivot != column) augmented[c(column,pivot),] <- augmented[c(pivot,column),,drop=FALSE]
    if (column < n) for (row in seq.int(column+1L,n)) {
      factor <- augmented[row,column]/augmented[column,column]
      for (c in seq.int(column,2L*n+1L)) augmented[row,c] <- augmented[row,c]-factor*augmented[column,c]
    }
  }
  solutions <- list()
  for (column in seq.int(n+1L,2L*n+1L)) {
    solution <- numeric(n)
    for (i in seq.int(n,1L)) {
      current <- augmented[i,column]
      if (i < n) for (j in seq.int(i+1L,n)) current <- current-augmented[i,j]*solution[j]
      solution[i] <- current/augmented[i,i]
    }
    solutions[[length(solutions)+1L]] <- solution
  }
  list(coefficients=solutions[[1L]],inverse=do.call(cbind,solutions[-1L]))
}
fit <- function(values,times,selected) {
  n <- 2L*length(selected)+1L
  matrix <- matrix(0,n,n)
  right <- numeric(n)
  for (t in times) {
    vector <- regressors(t,selected)
    observed <- values[[as.character(t)]]
    for (i in seq_len(n)) {
      right[i] <- right[i]+vector[i]*observed
      for (j in seq_len(n)) matrix[i,j] <- matrix[i,j]+vector[i]*vector[j]
    }
  }
  solved <- solve_with_inverse(matrix,right)
  coefficients <- solved$coefficients
  constants <- list()
  for (k in seq_along(selected)) {
    c <- selected[[k]]
    a <- coefficients[2L*k]
    b <- coefficients[2L*k+1L]
    amplitude <- sqrt(a*a+b*b)
    phase <- atan2(b,a)*180/TIDE_PI
    if (phase < 0) phase <- phase+360
    constants[[c$name]] <- list(
        speed=c$speed,
        a=a,
        b=b,
        amplitude=amplitude,
        phase=phase,
        index_a=2L*k,
        index_b=2L*k+1L
    )
  }
  list(
      selected=selected,
      coefficients=coefficients,
      inverse=solved$inverse,
      mean_level=coefficients[1L],
      constants=constants,
      unknowns=n
  )
}
