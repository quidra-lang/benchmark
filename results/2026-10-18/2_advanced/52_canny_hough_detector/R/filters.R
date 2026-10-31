clamped <- function(image,x,y) image[min(max(y+1L,1L),nrow(image)),min(max(x+1L,1L),ncol(image))]
smoothing <- function(image,params) {
  height <- nrow(image)
  width <- ncol(image)
  ks <- params$gauss_size[1L]
  half <- ks %/% 2L
  weights <- params$gauss_kernel
  divisor <- params$gauss_divisor[1L]
  output <- matrix(0L,height,width)
  for (y in seq_len(height)-1L) for (x in seq_len(width)-1L) {
    total <- 0
    for (j in seq_len(ks)-1L) for (i in seq_len(ks)-1L) total <- total+weights[j*ks+i+1L]*clamped(
        image,
        x+i-half,
        y+j-half
    )
    output[y+1L,x+1L] <- total %/% divisor
  }
  output
}
gradient <- function(image) {
  height <- nrow(image)
  width <- ncol(image)
  gx <- gy <- magnitude <- matrix(0L,height,width)
  for (y in seq_len(height)-1L) for (x in seq_len(width)-1L) {
    q1 <- clamped(image,x-1L,y-1L)
    q2 <- clamped(image,x,y-1L)
    q3 <- clamped(image,x+1L,y-1L)
    q4 <- clamped(image,x-1L,y)
    q6 <- clamped(image,x+1L,y)
    q7 <- clamped(image,x-1L,y+1L)
    q8 <- clamped(image,x,y+1L)
    q9 <- clamped(image,x+1L,y+1L)
    dx <- (q3+2L*q6+q9)-(q1+2L*q4+q7)
    dy <- (q7+2L*q8+q9)-(q1+2L*q2+q3)
    gx[y+1L,x+1L] <- dx
    gy[y+1L,x+1L] <- dy
    magnitude[y+1L,x+1L] <- abs(dx)+abs(dy)
  }
  list(gx=gx,gy=gy,magnitude=magnitude)
}
