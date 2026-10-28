ordered_sum <- function(values) {
  total <- 0
  for (value in values) total <- total+value
  total
}
heat_flow <- function(system,field,point,directions) {
  total <- 0
  for (direction in directions) {
    face <- system$faces[[point]][[direction]]
    if (face$neighbor != 0L) total <- total+face$g*(field[face$neighbor]-field[point]) else if (!is.null(face$theta)) total <- total+face$g*(face$theta-field[point])
  }
  total
}
horizontal_flow <- function(system,field,p) heat_flow(system,field,p,c(LEFT,RIGHT))
vertical_flow <- function(system,field,p) heat_flow(system,field,p,c(TOP,BOTTOM))
total_flow <- function(system,field,p) heat_flow(system,field,p,c(LEFT,RIGHT,TOP,BOTTOM))
thomas <- function(lower,diagonal,upper,rhs) {
  n <- length(diagonal)
  upper_prime <- rhs_prime <- numeric(n)
  upper_prime[1L] <- upper[1L]/diagonal[1L]
  rhs_prime[1L] <- rhs[1L]/diagonal[1L]
  if (n > 1L) for (i in seq.int(2L,n)) {
    pivot <- diagonal[i]-lower[i]*upper_prime[i-1L]
    upper_prime[i] <- upper[i]/pivot
    rhs_prime[i] <- (rhs[i]-lower[i]*rhs_prime[i-1L])/pivot
  }
  result <- numeric(n)
  result[n] <- rhs_prime[n]
  if (n > 1L) for (i in seq.int(n-1L,1L)) result[i] <- rhs_prime[i]-upper_prime[i]*result[i+1L]
  result
}
sweep_field <- function(system,tau,right_hand_side,horizontal) {
  plate <- system$mesh
  line_count <- if (horizontal) plate$height else plate$width
  line_length <- if (horizontal) plate$width else plate$height
  first_face <- if (horizontal) LEFT else TOP
  second_face <- if (horizontal) RIGHT else BOTTOM
  field <- numeric(plate$count)
  for (line in seq_len(line_count)-1L) {
    cells <- vapply(
        seq_len(line_length)-1L,
        function(i) if (horizontal) cell(plate,line,i) else cell(plate,i,line),
        integer(1)
    )
    lower <- diagonal <- upper <- rhs <- numeric(line_length)
    for (i in seq_along(cells)) {
      p <- cells[i]
      first <- system$faces[[p]][[first_face]]
      second <- system$faces[[p]][[second_face]]
      lower[i] <- if (first$neighbor != 0L) -first$g else 0
      diagonal[i] <- system$capacity[p]/tau+first$g+second$g
      upper[i] <- if (second$neighbor != 0L) -second$g else 0
      value <- right_hand_side[p]
      if (!is.null(first$theta)) value <- value+first$g*first$theta
      if (!is.null(second$theta)) value <- value+second$g*second$theta
      rhs[i] <- value
    }
    field[cells] <- thomas(lower,diagonal,upper,rhs)
  }
  field
}
horizontal_sweep <- function(system,tau,rhs) sweep_field(system,tau,rhs,TRUE)
vertical_sweep <- function(system,tau,rhs) sweep_field(system,tau,rhs,FALSE)
advance_field <- function(method,system,field,source,dt) {
  indices <- seq_len(system$mesh$count)
  if (method == "ftcs") return(list(
      field=vapply(
          indices,
          function(p) field[p]+dt*(total_flow(system,field,p)+source[p])/system$capacity[p],
          numeric(1)
      ),
      intermediate=NULL
  ))
  if (method == "backward_euler") {
    vertical <- vapply(indices,function(p) vertical_flow(system,field,p),numeric(1))
    rhs <- system$capacity/dt*field+vertical+source
    intermediate <- horizontal_sweep(system,dt,rhs)
    rhs <- system$capacity/dt*intermediate-vertical
    return(list(field=vertical_sweep(system,dt,rhs),intermediate=intermediate))
  }
  tau <- dt/2
  rhs <- vapply(
      indices,
      function(p) system$capacity[p]/tau*field[p]+vertical_flow(system,field,p)+source[p],
      numeric(1)
  )
  intermediate <- horizontal_sweep(system,tau,rhs)
  rhs <- vapply(
      indices,
      function(p) system$capacity[p]/tau*intermediate[p]+horizontal_flow(system,intermediate,p)+source[p],
      numeric(1)
  )
  list(field=vertical_sweep(system,tau,rhs),intermediate=intermediate)
}
