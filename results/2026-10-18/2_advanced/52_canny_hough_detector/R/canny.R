NEIGHBORS <- list(c(-1L,-1L),c(0L,-1L),c(1L,-1L),c(-1L,0L),c(1L,0L),c(-1L,1L),c(0L,1L),c(1L,1L))
raster_points <- function(mask) {
  indices <- which(mask,arr.ind=TRUE)
  indices <- indices[order(indices[,1L],indices[,2L]),,drop=FALSE]
  lapply(seq_len(nrow(indices)),function(i) c(indices[i,2L]-1L,indices[i,1L]-1L))
}
has_edge <- function(mask,x,y) x >= 0L && x < ncol(mask) && y >= 0L && y < nrow(mask) && mask[y+1L,x+1L]
directions <- function(gx,gy) {
  direction <- matrix(0L,nrow(gx),ncol(gx))
  for (i in seq_along(gx)) {
    ax <- abs(gx[i])
    ay <- abs(gy[i])
    direction[i] <- if (29*ay <= 12*ax) 0L else if (29*ay >= 70*ax) 90L else if (gx[i]*gy[i] < 0L) 45L else 135L
  }
  direction
}
suppress <- function(magnitude,direction) {
  output <- matrix(0L,nrow(magnitude),ncol(magnitude))
  offsets <- list("0"=c(-1L,0L),"45"=c(1L,-1L),"90"=c(0L,-1L),"135"=c(-1L,-1L))
  for (y in seq.int(1L,nrow(magnitude)-2L)) for (x in seq.int(1L,ncol(magnitude)-2L)) {
    offset <- offsets[[as.character(direction[y+1L,x+1L])]]
    dx <- offset[1L]
    dy <- offset[2L]
    value <- magnitude[y+1L,x+1L]
    if (value > magnitude[y+dy+1L,x+dx+1L] && value >= magnitude[y-dy+1L,x-dx+1L]) output[y+1L,x+1L] <- value
  }
  output
}
hysteresis <- function(nonmax,low,high) {
  strong <- nonmax >= high
  weak <- nonmax >= low & nonmax < high
  edges <- strong
  queue <- raster_points(strong)
  cursor <- 1L
  while (cursor <= length(queue)) {
    point <- queue[[cursor]]
    cursor <- cursor+1L
    for (offset in NEIGHBORS) {
      q <- point+offset
      if (has_edge(weak,q[1L],q[2L]) && !has_edge(edges,q[1L],q[2L])) {
        edges[q[2L]+1L,q[1L]+1L] <- TRUE
        queue[[length(queue)+1L]] <- q
      }
    }
  }
  list(edges=edges,strong=strong,weak=weak)
}
components <- function(edges) {
  waiting <- edges
  found <- list()
  for (start in raster_points(edges)) {
    if (!waiting[start[2L]+1L,start[1L]+1L]) next
    waiting[start[2L]+1L,start[1L]+1L] <- FALSE
    queue <- list(start)
    cursor <- 1L
    while (cursor <= length(queue)) {
      point <- queue[[cursor]]
      cursor <- cursor+1L
      for (offset in NEIGHBORS) {
        q <- point+offset
        if (has_edge(waiting,q[1L],q[2L])) {
          waiting[q[2L]+1L,q[1L]+1L] <- FALSE
          queue[[length(queue)+1L]] <- q
        }
      }
    }
    found[[length(found)+1L]] <- queue
  }
  found
}
