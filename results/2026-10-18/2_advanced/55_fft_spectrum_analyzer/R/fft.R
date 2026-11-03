PI <- 3.141592653589793
rot <- function(angle) complex(real=cos(angle),imaginary=-sin(angle))
pow2 <- function(value) {
  result <- 1L
  while (result < value) result <- result*2L
  result
}
is_power_two <- function(value) bitwAnd(value,value-1L) == 0L
radix2 <- function(data,inverse=FALSE) {
  n <- length(data)
  values <- as.complex(data)
  bits <- as.integer(log2(n))
  if (n > 1L) for (i in seq_len(n-1L)) {
    reversed <- 0L
    t <- i
    for (unused in seq_len(bits)) {
      reversed <- 2L*reversed+t %% 2L
      t <- t %/% 2L
    }
    if (i < reversed) {
      temporary <- values[i+1L]
      values[i+1L] <- values[reversed+1L]
      values[reversed+1L] <- temporary
    }
  }
  twiddle <- rot(2*PI*(seq_len(n %/% 2L)-1L)/n)
  if (inverse) twiddle <- Conj(twiddle)
  span <- 2L
  while (span <= n) {
    stride <- n %/% span
    half <- span %/% 2L
    for (start in seq.int(0L,n-1L,by=span)) for (j in seq_len(half)-1L) {
      t <- twiddle[j*stride+1L]*values[start+j+half+1L]
      u <- values[start+j+1L]
      values[start+j+1L] <- u+t
      values[start+j+half+1L] <- u-t
    }
    span <- span*2L
  }
  if (inverse) values/n else values
}
bluestein <- function(values) {
  m <- length(values)
  q <- pow2(2L*m-1L)
  indices <- seq_len(m)-1L
  chirp <- rot(PI*((as.numeric(indices)*indices) %% (2L*m))/m)
  a <- b <- complex(q)
  for (n in indices) {
    a[n+1L] <- values[n+1L]*chirp[n+1L]
    b[n+1L] <- Conj(chirp[n+1L])
    if (n > 0L) b[q-n+1L] <- b[n+1L]
  }
  g <- radix2(radix2(a)*radix2(b),TRUE)
  chirp*g[seq_len(m)]
}
dft <- function(values) if (is_power_two(length(values))) radix2(values) else bluestein(values)
idft <- function(values) if (is_power_two(length(values))) radix2(
    values,
    TRUE
) else Conj(bluestein(Conj(values)))/length(values)
packed_real <- function(values) {
  n <- length(values)
  half <- n %/% 2L
  j <- seq_len(half)-1L
  transformed <- radix2(complex(real=values[2L*j+1L],imaginary=values[2L*j+2L]))
  result <- complex(half+1L)
  for (k in seq.int(0L,half)) {
    a <- transformed[k %% half+1L]
    b <- Conj(transformed[(half-k) %% half+1L])
    even <- (a+b)/2
    odd <- (a-b)/(2i)
    result[k+1L] <- even+rot(2*PI*k/n)*odd
  }
  result
}
convolution <- function(a,b) {
  n <- length(a)+length(b)-1L
  q <- pow2(n)
  af <- radix2(c(a,numeric(q-length(a))))
  bf <- radix2(c(b,numeric(q-length(b))))
  Re(radix2(af*bf,TRUE)[seq_len(n)])
}
chirp_z <- function(values,fs,low,high,points) {
  m <- length(values)
  step <- (high-low)/(points-1L)
  q <- pow2(m+points-1L)
  a <- b <- complex(q)
  for (n in seq_len(m)-1L) a[n+1L] <- values[n+1L]*rot(2*PI*low*n/fs)*rot(PI*step*n*n/fs)
  for (offset in seq.int(-(m-1L),points-1L)) b[offset %% q+1L] <- Conj(rot(PI*step*offset*offset/fs))
  g <- radix2(radix2(a)*radix2(b),TRUE)
  j <- seq_len(points)-1L
  rot(PI*step*j*j/fs)*g[seq_len(points)]
}
