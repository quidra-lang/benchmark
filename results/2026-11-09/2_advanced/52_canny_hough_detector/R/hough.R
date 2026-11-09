rho <- function(
    point,
    angle,
    trig,
    step
) (point[1L]*trig[angle+1L,1L]+point[2L]*trig[angle+1L,2L]) %/% (16384*step)
circle_points <- function(radius) {
  points <- list()
  a <- radius
  b <- 0L
  error <- 1L-radius
  while (a >= b) {
    points <- c(points,list(c(a,b),c(b,a),c(-b,a),c(-a,b),c(-a,-b),c(-b,-a),c(b,-a),c(a,-b)))
    b <- b+1L
    if (error < 0) error <- error+2L*b+1L else {
      a <- a-1L
      error <- error+2L*(b-a)+1L
    }
  }
  unique(points)
}
circle_votes <- function(edges,params) {
  cells <- outlines <- list()
  radii <- seq.int(params$circle_min_radius[1L],params$circle_max_radius[1L])
  points <- raster_points(edges)
  for (radius in radii) {
    offsets <- circle_points(radius)
    key <- as.character(radius)
    outlines[[key]] <- offsets
    votes <- matrix(0L,nrow(edges),ncol(edges))
    for (point in points) for (offset in offsets) {
      q <- point+offset
      if (q[1L] >= 0 && q[1L] < ncol(edges) && q[2L] >= 0 && q[2L] < nrow(edges)) votes[q[2L]+1L,q[1L]+1L] <- votes[
          q[2L]+1L,
          q[1L]+1L
      ]+1L
    }
    cells[[key]] <- votes
  }
  list(cells=cells,outlines=outlines,radii=radii)
}
circle_peaks <- function(cells,outlines,radii,width,height,minimum_percent) {
  candidates <- peaks <- list()
  for (radius in radii) for (y in seq_len(height)-1L) for (x in seq_len(width)-1L) {
    key <- as.character(radius)
    votes <- cells[[key]][y+1L,x+1L]
    n <- length(outlines[[key]])
    if (100*votes < minimum_percent*n) next
    cell <- list(radius=radius,x=x,y=y,votes=votes)
    candidates[[length(candidates)+1L]] <- cell
    peak <- TRUE
    for (r in radii[abs(radii-radius) <= 2L]) {
      if (!peak) break
      other_key <- as.character(r)
      for (yy in seq.int(max(0L,y-2L),min(height-1L,y+2L))) {
        if (!peak) break
        for (xx in seq.int(max(0L,x-2L),min(width-1L,x+2L))) {
          if (r == radius && yy == y && xx == x) next
          a <- votes*length(outlines[[other_key]])
          b <- cells[[other_key]][yy+1L,xx+1L]*n
          before <- r < radius || (r == radius && (yy < y || (yy == y && xx < x)))
          if (a < b || (a == b && before)) {
            peak <- FALSE
            break
          }
        }
      }
    }
    if (peak) peaks[[length(peaks)+1L]] <- cell
  }
  earlier <- function(a,b) {
    left <- a$votes*length(outlines[[as.character(b$radius)]])
    right <- b$votes*length(outlines[[as.character(a$radius)]])
    if (left != right) return(left > right)
    if (a$radius != b$radius) return(a$radius < b$radius)
    if (a$y != b$y) return(a$y < b$y)
    a$x < b$x
  }
  ordered <- list()
  for (peak in peaks) {
    position <- 1L
    while (position <= length(ordered) && !earlier(peak,ordered[[position]])) position <- position+1L
    ordered <- append(ordered,list(peak),after=position-1L)
  }
  list(candidates=candidates,peaks=ordered)
}
line_votes <- function(edges,trig,step) {
  corners <- list(c(0L,0L),c(ncol(edges)-1L,0L),c(0L,nrow(edges)-1L),c(ncol(edges)-1L,nrow(edges)-1L))
  limits <- unlist(
      lapply(
          seq_len(180L)-1L,
          function(angle) vapply(corners,function(point) rho(point,angle,trig,step),numeric(1))
      ),
      use.names=FALSE
  )
  low <- min(limits)
  high <- max(limits)
  votes <- matrix(0L,high-low+1L,180L)
  for (point in raster_points(edges)) for (angle in seq_len(180L)-1L) {
    row <- rho(point,angle,trig,step)-low+1L
    votes[row,angle+1L] <- votes[row,angle+1L]+1L
  }
  list(votes=votes,low=low,high=high,maximum=max(votes))
}
line_vote <- function(votes,angle,radial) {
  if (angle < 0L || angle > 179L || radial < votes$low || radial > votes$high) 0L else votes$votes[
      radial-votes$low+1L,
      angle+1L
  ]
}
line_peaks <- function(votes,threshold) {
  peaks <- list()
  for (angle in seq_len(180L)-1L) for (radial in seq.int(votes$low,votes$high)) {
    value <- line_vote(votes,angle,radial)
    if (value < threshold) next
    peak <- TRUE
    for (t in seq.int(max(0L,angle-2L),min(179L,angle+2L))) {
      if (!peak) break
      for (r in seq.int(radial-2L,radial+2L)) {
        if (t == angle && r == radial) next
        other <- line_vote(votes,t,r)
        before <- t < angle || (t == angle && r < radial)
        if (other > value || (other == value && before)) {
          peak <- FALSE
          break
        }
      }
    }
    if (peak) peaks[[length(peaks)+1L]] <- list(theta=angle,rho=radial,votes=value)
  }
  peaks[order(
      -vapply(peaks,function(p) p$votes,integer(1)),
      vapply(peaks,function(p) p$theta,integer(1)),
      vapply(peaks,function(p) p$rho,numeric(1))
  )]
}
