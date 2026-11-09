orient <- function(p,q,r) (q[1L]-p[1L])*(r[2L]-p[2L])-(q[2L]-p[2L])*(r[1L]-p[1L])
d2 <- function(p,q) (p[1L]-q[1L])^2+(p[2L]-q[2L])^2
dot_at <- function(o,p,q) (p[1L]-o[1L])*(q[1L]-o[1L])+(p[2L]-o[2L])*(q[2L]-o[2L])
incircle <- function(a,b,c,d) {
  ax <- a[1L]-d[1L]
  ay <- a[2L]-d[2L]
  bx <- b[1L]-d[1L]
  by <- b[2L]-d[2L]
  cx <- c[1L]-d[1L]
  cy <- c[2L]-d[2L]
  aa <- ax*ax+ay*ay
  bb <- bx*bx+by*by
  cc <- cx*cx+cy*cy
  ax*(by*cc-bb*cy)-ay*(bx*cc-bb*cx)+aa*(bx*cy-by*cx)
}
circumcenter <- function(a,b,c) {
  bx <- b[1L]-a[1L]
  by <- b[2L]-a[2L]
  cx <- c[1L]-a[1L]
  cy <- c[2L]-a[2L]
  bb <- bx*bx+by*by
  cc <- cx*cx+cy*cy
  denominator <- 2*(bx*cy-by*cx)
  c(a[1L]*denominator+cy*bb-by*cc,a[2L]*denominator+bx*cc-cx*bb,denominator)
}
gcd <- function(a,b) {
  a <- abs(a)
  b <- abs(b)
  while (b != 0) {
    remainder <- a %% b
    a <- b
    b <- remainder
  }
  a
}
integer_text <- function(value) sprintf("%.0f",value)
fraction <- function(n,d) {
  common <- gcd(n,d)
  n <- n/common
  d <- d/common
  if (d == 1) integer_text(n) else paste0(integer_text(n),"/",integer_text(d))
}
reduce_direction <- function(dx,dy) c(dx,dy)/gcd(dx,dy)
