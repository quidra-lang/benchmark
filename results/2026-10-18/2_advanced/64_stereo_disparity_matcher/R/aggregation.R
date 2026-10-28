DIRECTIONS <- list(c(1L,0L),c(-1L,0L),c(0L,1L),c(0L,-1L),c(1L,1L),c(-1L,-1L),c(-1L,1L),c(1L,-1L))
path_costs <- function(base,left,width,height,direction,p1,p2,gamma) {
  rx <- direction[1L]
  ry <- direction[2L]
  rows <- if (ry >= 0L) 0:(height-1L) else (height-1L):0
  columns <- if (rx >= 0L) 0:(width-1L) else (width-1L):0
  result <- matrix(0,nrow(base),ncol(base))
  for (y in rows) for (x in columns) {
    p <- y*width+x+1L
    qx <- x-rx
    qy <- y-ry
    if (!(qx >= 0L && qx < width && qy >= 0L && qy < height)) {
      result[p,] <- base[p,]
      next
    }
    q <- qy*width+qx+1L
    previous <- result[q,]
    smallest <- min(previous)
    penalty <- max(p1,(p2*gamma) %/% (gamma+abs(left[p]-left[q])))
    for (d in seq_len(ncol(base))) {
      best <- min(previous[d],smallest+penalty)
      if (d > 1L) best <- min(best,previous[d-1L]+p1)
      if (d < ncol(base)) best <- min(best,previous[d+1L]+p1)
      result[p,d] <- base[p,d]+best-smallest
    }
  }
  result
}
cumulative_costs <- function(base,left,width,height,paths,p1,p2,gamma) {
  total <- matrix(0,nrow(base),ncol(base))
  result <- list()
  for (direction in DIRECTIONS[seq_len(paths)]) {
    total <- total+path_costs(base,left,width,height,direction,p1,p2,gamma)
    result[[length(result)+1L]] <- total
  }
  result
}
