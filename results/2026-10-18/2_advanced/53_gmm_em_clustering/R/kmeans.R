squared_distance <- function(a,b) {
  dx <- a[1L]-b[1L]
  dy <- a[2L]-b[2L]
  dx*dx+dy*dy
}
distance <- function(a,b) sqrt(squared_distance(a,b))
assignments <- function(points,centers) vapply(
    points,
    function(point) which.min(vapply(
        centers,
        function(center) squared_distance(point_xy(point),center),
        numeric(1)
    )),
    integer(1)
)
run_kmeans <- function(points,initial_centers,max_iterations) {
  centers <- initial_centers
  assigned <- assignments(points,centers)
  iterations <- 0L
  for (t in seq_len(max_iterations)) {
    next_centers <- lapply(seq_along(centers),function(k) {
      members <- points[assigned == k]
      if (!length(members)) return(centers[[k]])
      c(
          ordered_sum(vapply(members,function(p) p$x,numeric(1)))/length(members),
          ordered_sum(vapply(members,function(p) p$y,numeric(1)))/length(members)
      )
    })
    centers <- next_centers
    next_assignment <- assignments(points,centers)
    iterations <- t
    if (identical(next_assignment,assigned)) {
      assigned <- next_assignment
      break
    }
    assigned <- next_assignment
  }
  inertia <- ordered_sum(vapply(
      seq_along(points),
      function(i) squared_distance(point_xy(points[[i]]),centers[[assigned[i]]]),
      numeric(1)
  ))
  list(
      centers=centers,
      assignment=assigned,
      iterations=iterations,
      inertia=inertia,
      sizes=vapply(seq_along(centers),function(k) sum(assigned == k),integer(1))
  )
}
