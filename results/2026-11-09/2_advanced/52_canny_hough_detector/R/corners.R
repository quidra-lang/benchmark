harris_corners <- function(gx,gy,window,threshold,maximum_count) {
  height <- nrow(gx)
  width <- ncol(gx)
  half <- window %/% 2L
  response <- matrix(0,height,width)
  for (y in seq_len(height)-1L) for (x in seq_len(width)-1L) {
    xx <- yy <- xy <- 0
    for (dy in seq.int(-half,half)) for (dx in seq.int(-half,half)) {
      a <- as.numeric(clamped(gx,x+dx,y+dy))
      b <- as.numeric(clamped(gy,x+dx,y+dy))
      xx <- xx+a*a
      yy <- yy+b*b
      xy <- xy+a*b
    }
    response[y+1L,x+1L] <- xx*yy-xy*xy-((xx+yy)*(xx+yy)) %/% 25
  }
  candidates <- list()
  for (y in seq_len(height)-1L) for (x in seq_len(width)-1L) {
    value <- response[y+1L,x+1L]
    if (value < threshold) next
    keep <- TRUE
    for (offset in NEIGHBORS) {
      nx <- x+offset[1L]
      ny <- y+offset[2L]
      if (nx < 0L || nx >= width || ny < 0L || ny >= height) next
      other <- response[ny+1L,nx+1L]
      before <- ny < y || (ny == y && nx < x)
      if (other > value || (other == value && before)) {
        keep <- FALSE
        break
      }
    }
    if (keep) candidates[[length(candidates)+1L]] <- list(x=x,y=y,response=value)
  }
  candidates <- candidates[order(
      -vapply(candidates,function(c) c$response,numeric(1)),
      vapply(candidates,function(c) c$y,integer(1)),
      vapply(candidates,function(c) c$x,integer(1))
  )]
  chosen <- head(candidates,maximum_count)
  for (i in seq_along(chosen)) chosen[[i]]$number <- i
  list(response=response,candidates=candidates,chosen=chosen)
}
