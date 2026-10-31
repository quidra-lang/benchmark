member_geometry <- function(nodes,members,node_dofs) {
  lapply(members,function(m) {
    start <- nodes[[m$start]]
    finish <- nodes[[m$finish]]
    dx <- finish$x-start$x
    dy <- finish$y-start$y
    span <- sqrt(dx*dx+dy*dy)
    list(length=span,cosine=dx/span,sine=dy/span,dofs=c(node_dofs[[m$start]],node_dofs[[m$finish]]))
  })
}
member_properties <- function(model,choices,geometry) {
  lapply(seq_along(model$members),function(i) {
    member <- model$members[[i]]
    section <- model$sections[[choices[i]]]
    material <- model$materials[[member$material]]
    list(
        area=section$area,
        inertia=section$inertia,
        young=material$young,
        yield_stress=material$yield_stress,
        density=material$density,
        expansion=material$expansion,
        stiffness=material$young*section$area/geometry[[i]]$length
    )
  })
}
member_weight <- function(p,g) p$density*9.81*p$area*g$length/1000000000
member_stiffness <- function(p,g) {
  k <- p$stiffness
  c <- g$cosine
  s <- g$sine
  xx <- k*(c*c)
  xy <- k*(c*s)
  yy <- k*(s*s)
  matrix(c(xx,xy,-xx,-xy,xy,yy,-xy,-yy,-xx,-xy,xx,xy,-xy,-yy,xy,yy),4L,4L,byrow=TRUE)
}
assemble <- function(geometry,properties,degrees,removed=0L) {
  matrix <- matrix(0,degrees,degrees)
  for (number in seq_along(geometry)) {
    if (number == removed) next
    shape <- geometry[[number]]
    local <- member_stiffness(properties[[number]],shape)
    for (row in seq_len(4L)) for (column in seq_len(4L)) matrix[shape$dofs[row],shape$dofs[column]] <- matrix[
        shape$dofs[row],
        shape$dofs[column]
    ]+local[row,column]
  }
  matrix
}
load_vectors <- function(case,geometry,properties,node_dofs,degrees,removed=0L) {
  external <- thermal <- numeric(degrees)
  temperature <- numeric(length(geometry))
  settlement <- FALSE
  for (line in case$lines) {
    if (line$kind == "FORCE") {
      directions <- node_dofs[[line$node]]
      external[directions[1L]] <- external[directions[1L]]+line$horizontal*1000
      external[directions[2L]] <- external[directions[2L]]+line$vertical*1000
    } else if (line$kind == "TEMPERATURE") {
      number <- line$member
      if (number == removed) next
      p <- properties[[number]]
      g <- geometry[[number]]
      force <- p$young*p$area*p$expansion*line$change
      temperature[number] <- force
      direction <- c(-g$cosine,-g$sine,g$cosine,g$sine)
      for (i in seq_len(4L)) thermal[g$dofs[i]] <- thermal[g$dofs[i]]+force*direction[i]
    } else if (line$kind == "SELFWEIGHT") for (number in seq_along(geometry)) {
      if (number == removed) next
      g <- geometry[[number]]
      weight <- member_weight(properties[[number]],g)
      external[g$dofs[2L]] <- external[g$dofs[2L]]-weight/2
      external[g$dofs[4L]] <- external[g$dofs[4L]]-weight/2
    } else settlement <- TRUE
  }
  list(external=external,total=external+thermal,temperature=temperature,settlement=settlement)
}
