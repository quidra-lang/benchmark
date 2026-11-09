REGION_ORDER <- c("nonocc","all","disc")
truth_regions <- function(truth,width,height) {
  known <- which(truth != 0)
  occluded <- integer()
  for (p in known) {
    y <- (p-1L) %/% width
    x <- (p-1L) %% width
    g <- truth[p]
    target <- x-g
    row <- truth[seq.int(y*width+1L,(y+1L)*width)]
    if (target < 0 || any(row > g & 0:(width-1L)-row == target)) occluded <- c(occluded,p)
  }
  visible <- setdiff(known,occluded)
  disc <- integer()
  for (p in visible) {
    y <- (p-1L) %/% width
    x <- (p-1L) %% width
    adjacent <- integer()
    for (yy in max(0L,y-1L):min(height-1L,y+1L)) for (xx in max(0L,x-1L):min(width-1L,x+1L)) adjacent <- c(
        adjacent,
        yy*width+xx+1L
    )
    if (any(truth[adjacent] != 0 & abs(truth[adjacent]-truth[p]) >= 2)) disc <- c(disc,p)
  }
  list(all=known,nonocc=visible,disc=disc,occluded=occluded)
}
evaluate <- function(image,truth,region) {
  valid_pixels <- region[image[region] != 0]
  errors <- abs(image[valid_pixels]-truth[valid_pixels])
  valid <- length(errors)
  missing <- length(region)-valid
  total <- sum(errors)
  list(
      pixels=length(region),
      valid=valid,
      bad1=missing+sum(errors > 1),
      bad2=missing+sum(errors > 2),
      error_sum=total,
      mae=if (valid) two_decimals(total,valid) else "-",
      exact=sum(errors == 0)
  )
}
integer_gcd <- function(a,b) {
  while (b != 0) {
    remainder <- a %% b
    a <- b
    b <- remainder
  }
  a
}
ratio <- function(a,b) {
  if (b == 0) return("0/1 0.00")
  divisor <- integer_gcd(a,b)
  paste0(integer_text(a %/% divisor),"/",integer_text(b %/% divisor)," ",two_decimals(100*a,b))
}
