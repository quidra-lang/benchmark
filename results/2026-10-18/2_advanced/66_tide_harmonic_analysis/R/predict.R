predict_height <- function(model,time) {
  result <- model$mean_level
  for (c in model$selected) {
    constant <- model$constants[[c$name]]
    theta <- tide_angle(c$speed,time)
    result <- result+constant$a*cos(theta)+constant$b*sin(theta)
  }
  result
}
predict_hours <- function(model,start,n) vapply(0:n,function(i) predict_height(model,start+i),numeric(1))
find_extrema <- function(model,start,hours,grid_minutes) {
  n <- (hours*60L) %/% grid_minutes
  minutes <- 60L*start+(0:n)*grid_minutes
  heights <- vapply(minutes,function(m) predict_height(model,m/60),numeric(1))
  extrema <- list()
  for (j in seq.int(2L,n)) {
    left <- heights[j-1L]
    center <- heights[j]
    right <- heights[j+1L]
    kind <- if (left < center && center > right) "high" else if (left > center && center < right) "low" else ""
    if (kind == "") next
    delta <- (left-right)/(2*(left-2*center+right))
    minute <- minutes[j]+delta*grid_minutes
    extrema[[length(extrema)+1L]] <- list(kind=kind,minute=minute,height=center-(left-right)*delta/4)
  }
  extrema
}
