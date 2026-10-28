hundredths <- function(value) paste0(integer_text(value %/% 100),".",sprintf("%02.0f",value %% 100))
two_decimals <- function(a,b=1) hundredths((200*a+b) %/% (2*b))
depth_hundredths <- function(d,focal,baseline) (200*focal*baseline+d) %/% (2*d)
subpixel <- function(d,costs,dmin,dmax,focal,baseline) {
  i <- d-dmin+1L
  a <- 0
  b <- 1
  if (dmin < d && d < dmax && costs[i-1L] > costs[i] && costs[i+1L] >= costs[i]) {
    a <- costs[i-1L]-costs[i+1L]
    b <- 2*(costs[i-1L]-2*costs[i]+costs[i+1L])
  }
  rounded <- (200*(d*b+a)+b) %/% (2*b)
  c(hundredths(rounded),two_decimals(100*focal*baseline,rounded))
}
