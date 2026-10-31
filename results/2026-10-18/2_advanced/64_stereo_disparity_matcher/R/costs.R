clamped <- function(image,width,height,x,y) image[min(max(y,0L),height-1L)*width+min(max(x,0L),width-1L)+1L]
box_sum <- function(image,width,height,window) {
  radius <- window %/% 2
  padded_width <- width+2*radius
  padded_height <- height+2*radius
  integral <- matrix(0,padded_height+1L,padded_width+1L)
  for (y in 0:(padded_height-1L)) {
    row_sum <- 0
    for (x in 0:(padded_width-1L)) {
      row_sum <- row_sum+clamped(image,width,height,x-radius,y-radius)
      integral[y+2L,x+2L] <- integral[y+1L,x+2L]+row_sum
    }
  }
  result <- numeric(width*height)
  for (y in 0:(height-1L)) for (x in 0:(width-1L)) result[y*width+x+1L] <- integral[
      y+window+1L,
      x+window+1L
  ]-integral[y+1L,x+window+1L]-integral[y+window+1L,x+1L]+integral[y+1L,x+1L]
  result
}
census <- function(image,width,height) {
  result <- integer(width*height)
  for (y in 0:(height-1L)) for (x in 0:(width-1L)) {
    code <- 0L
    center <- image[y*width+x+1L]
    for (dy in -2:2) for (dx in -2:2) {
      if (dx == 0L && dy == 0L) next
      code <- 2L*code+as.integer(clamped(image,width,height,x+dx,y+dy) < center)
    }
    result[y*width+x+1L] <- code
  }
  result
}
texture <- function(image,width,height,window) {
  gradient <- numeric(width*height)
  for (y in 0:(height-1L)) for (x in 0:(width-1L)) gradient[y*width+x+1L] <- abs(clamped(image,width,height,x+1L,y)-clamped(
      image,
      width,
      height,
      x-1L,
      y
  ))
  box_sum(gradient,width,height,window)
}
popcount <- function(value) {
  count <- 0L
  while (value != 0L) {
    count <- count+value %% 2L
    value <- value %/% 2L
  }
  count
}
cost_volume <- function(left,right,cl,cr,width,height,kind,window,dmin,dmax) {
  volume <- matrix(0,length(left),dmax-dmin+1L)
  for (d in dmin:dmax) {
    pixels <- numeric(length(left))
    for (y in 0:(height-1L)) for (x in 0:(width-1L)) {
      p <- y*width+x+1L
      q <- y*width+max(x-d,0L)+1L
      difference <- left[p]-right[q]
      pixels[p] <- if (kind == "census") popcount(bitwXor(
          cl[p],
          cr[q]
      )) else if (kind == "sad") abs(difference) else difference*difference
    }
    volume[,d-dmin+1L] <- box_sum(pixels,width,height,window)
  }
  volume
}
