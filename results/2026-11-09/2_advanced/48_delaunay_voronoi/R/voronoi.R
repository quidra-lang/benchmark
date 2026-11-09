squared_radius <- function(a,b,c) {
  l1 <- d2(a,b)
  l2 <- d2(b,c)
  l3 <- d2(c,a)
  area <- orient(a,b,c)
  ((l1*l2)*l3)/((4*area)*area)
}
center_position <- function(center,points,hull) {
  x <- center[1L]
  y <- center[2L]
  denominator <- center[3L]
  on <- FALSE
  for (i in seq_along(hull)) {
    u <- points[[hull[i]]]
    v <- points[[hull[i %% length(hull)+1L]]]
    sigma <- (v[1L]-u[1L])*(y-u[2L]*denominator)-(v[2L]-u[2L])*(x-u[1L]*denominator)
    if (sigma < 0) return("outside")
    on <- on || sigma == 0
  }
  if (on) "on" else "inside"
}
neighbor_order <- function(s,neighbors,directed,hull_next) {
  start <- if (hull_next[s] != 0L) hull_next[s] else min(neighbors)
  order <- start
  while (length(order) < length(neighbors)) order <- c(order,directed[s,tail(order,1L)])
  order
}
outward <- function(points,u,v) {
  dx <- points[[v]][1L]-points[[u]][1L]
  dy <- points[[v]][2L]-points[[u]][2L]
  reduce_direction(dy,-dx)
}
bounded_area <- function(site,centers) {
  relative <- lapply(centers,function(center) center[1:2]/center[3L]-site)
  total <- 0
  for (i in seq_along(relative)) {
    p <- relative[[i]]
    q <- relative[[i %% length(relative)+1L]]
    total <- total+(p[1L]*q[2L]-q[1L]*p[2L])
  }
  total/2
}
clipped_area <- function(points,s,neighbors) {
  polygon <- list(c(0,0),c(1000,0),c(1000,1000),c(0,1000))
  xs <- points[[s]][1L]
  ys <- points[[s]][2L]
  for (t in neighbors) {
    xt <- points[[t]][1L]
    yt <- points[[t]][2L]
    c1 <- 2*(xt-xs)
    c2 <- 2*(yt-ys)
    c3 <- xt*xt+yt*yt-xs*xs-ys*ys
    clipped <- list()
    for (i in seq_along(polygon)) {
      p <- polygon[[i]]
      q <- polygon[[i %% length(polygon)+1L]]
      fp <- c1*p[1L]+c2*p[2L]-c3
      fq <- c1*q[1L]+c2*q[2L]-c3
      if (fp <= 0) clipped[[length(clipped)+1L]] <- p
      if ((fp < 0 && fq > 0) || (fq < 0 && fp > 0)) {
        lambda <- fp/(fp-fq)
        clipped[[length(clipped)+1L]] <- p+(q-p)*lambda
      }
    }
    polygon <- clipped
  }
  total <- 0
  for (i in seq_along(polygon)) {
    p <- polygon[[i]]
    q <- polygon[[i %% length(polygon)+1L]]
    total <- total+(p[1L]*q[2L]-q[1L]*p[2L])
  }
  total/2
}
