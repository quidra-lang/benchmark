make_canvas <- function(width,height) {
  canvas <- new.env(parent=emptyenv())
  canvas$width <- width
  canvas$height <- height
  canvas$rows <- matrix(" ",height,width)
  canvas
}
canvas_position <- function(canvas,point) {
  denominator <- if (length(point) == 3L) point[3L] else 1
  column <- (2*point[1L]*(canvas$width-1L)+1000*denominator) %/% (2000*denominator)
  row <- canvas$height-1L-(2*point[2L]*(canvas$height-1L)+1000*denominator) %/% (2000*denominator)
  c(column,row)
}
mark <- function(canvas,point,character) {
  position <- canvas_position(canvas,point)+1L
  canvas$rows[position[2L],position[1L]] <- character
}
draw_line <- function(canvas,a,b,character) {
  first <- canvas_position(canvas,a)
  last <- canvas_position(canvas,b)
  x <- first[1L]
  y <- first[2L]
  dx <- abs(last[1L]-x)
  dy <- -abs(last[2L]-y)
  sx <- if (x < last[1L]) 1L else -1L
  sy <- if (y < last[2L]) 1L else -1L
  error <- dx+dy
  repeat {
    canvas$rows[y+1L,x+1L] <- character
    if (x == last[1L] && y == last[2L]) break
    twice <- 2L*error
    if (twice >= dy) {
      error <- error+dy
      x <- x+sx
    }
    if (twice <= dx) {
      error <- error+dx
      y <- y+sy
    }
  }
}
draw_voronoi <- function(canvas,points) {
  horizontal <- canvas$width-1L
  vertical <- canvas$height-1L
  owners <- matrix(0L,canvas$height,canvas$width)
  for (r in seq_len(canvas$height)-1L) for (column in seq_len(canvas$width)-1L) {
    best <- Inf
    for (s in seq_along(points)) {
      x <- points[[s]][1L]
      y <- points[[s]][2L]
      dx <- (column*1000-x*horizontal)*vertical
      dy <- ((vertical-r)*1000-y*vertical)*horizontal
      distance <- dx*dx+dy*dy
      if (distance < best) {
        owners[r+1L,column+1L] <- s
        best <- distance
      }
    }
  }
  for (r in seq_len(canvas$height)-1L) for (column in seq_len(canvas$width)-1L) {
    owner <- owners[r+1L,column+1L]
    if ((column < horizontal && owner != owners[r+1L,column+2L]) || (r < vertical && owner != owners[
        r+2L,
        column+1L
    ]))
      canvas$rows[r+1L,column+1L] <- "#"
  }
  for (point in points) mark(canvas,point,"o")
}
framed <- function(canvas) {
  border <- paste0("+",strrep("-",canvas$width),"+")
  c(
      border,
      vapply(
          seq_len(canvas$height),
          function(r) paste0("|",paste(canvas$rows[r,],collapse=""),"|"),
          character(1)
      ),
      border
  )
}
