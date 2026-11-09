clamp_byte <- function(value) min(max(value,0),255)
to_ycbcr <- function(pixel) {
  r <- pixel[1L]
  g <- pixel[2L]
  b <- pixel[3L]
  c(
      (19595*r+38470*g+7471*b+32768) %/% 65536,
      (-11059*r-21709*g+32768*b+8421375) %/% 65536,
      (32768*r-27439*g-5329*b+8421375) %/% 65536
  )
}
to_rgb <- function(y,cb,cr) {
  c(
      clamp_byte(y+(91881*(cr-128)+32768) %/% 65536),
      clamp_byte(y+(-22554*(cb-128)-46802*(cr-128)+32768) %/% 65536),
      clamp_byte(y+(116130*(cb-128)+32768) %/% 65536)
  )
}
split_planes <- function(image) {
  height <- dim(image)[1L]
  width <- dim(image)[2L]
  planes <- lapply(1:3,function(unused) matrix(0,height,width))
  for (y in seq_len(height)) for (x in seq_len(width)) {
    values <- to_ycbcr(image[y,x,])
    for (k in 1:3) planes[[k]][y,x] <- values[k]
  }
  planes
}
component_planes <- function(planes,factors,mx,my) {
  height <- nrow(planes[[1L]])
  width <- ncol(planes[[1L]])
  hmax <- max(vapply(factors,function(f) f[1L],integer(1)))
  vmax <- max(vapply(factors,function(f) f[2L],integer(1)))
  result <- list()
  for (k in seq_along(planes)) {
    h <- factors[[k]][1L]
    v <- factors[[k]][2L]
    fx <- hmax %/% h
    fy <- vmax %/% v
    component <- matrix(0,8L*v*my,8L*h*mx)
    for (y in 0:(nrow(component)-1L)) for (x in 0:(ncol(component)-1L)) {
      total <- 0
      for (j in 0:(fy-1L)) for (i in 0:(fx-1L)) total <- total+planes[[k]][
          min(fy*y+j,height-1L)+1L,
          min(fx*x+i,width-1L)+1L
      ]
      component[y+1L,x+1L] <- total %/% (fx*fy)
    }
    result[[k]] <- component
  }
  result
}
upsample <- function(planes,factors,width,height) {
  hmax <- max(vapply(factors,function(f) f[1L],integer(1)))
  vmax <- max(vapply(factors,function(f) f[2L],integer(1)))
  lapply(seq_along(planes),function(k) {
    plane <- matrix(0,height,width)
    for (y in 0:(height-1L)) for (x in 0:(width-1L)) plane[y+1L,x+1L] <- planes[[k]][
        (y*factors[[k]][2L]) %/% vmax+1L,
        (x*factors[[k]][1L]) %/% hmax+1L
    ]
    plane
  })
}
combine_rgb <- function(planes) {
  image <- array(0,c(nrow(planes[[1L]]),ncol(planes[[1L]]),3L))
  for (y in seq_len(dim(image)[1L])) for (x in seq_len(dim(image)[2L])) image[y,x,] <- to_rgb(
      planes[[1L]][y,x],
      planes[[2L]][y,x],
      planes[[3L]][y,x]
  )
  image
}
