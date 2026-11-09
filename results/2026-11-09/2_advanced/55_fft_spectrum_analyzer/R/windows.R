WINDOW_ORDER <- c("rectangular","hann","hamming","blackman","flattop")
COEFFICIENTS <- list(
    rectangular=1,
    hann=c(0.5,0.5),
    hamming=c(0.54,0.46),
    blackman=c(0.42,0.5,0.08),
    flattop=c(0.21557895,0.41663158,0.277263158,0.083578947,0.006947368)
)
ordered_sum <- function(values) {
  total <- 0
  for (value in values) total <- total+value
  total
}
window <- function(name,n) {
  coefficients <- COEFFICIENTS[[name]]
  vapply(
      seq_len(n)-1L,
      function(i) ordered_sum(vapply(
          seq_along(coefficients)-1L,
          function(j) (-1)^j*coefficients[j+1L]*cos(2*PI*j*i/n),
          numeric(1)
      )),
      numeric(1)
  )
}
figures <- function(values,fs) {
  n <- length(values)
  s1 <- ordered_sum(values)
  s2 <- ordered_sum(values*values)
  magnitude <- Mod(ordered_sum(values*rot(PI*(seq_len(n)-1L)/n)))
  enbw <- n*s2/(s1*s1)
  list(s1=s1,s2=s2,coherent_gain=s1/n,enbw_bins=enbw,enbw_hz=enbw*fs/n,scalloping_db=-20*log10(magnitude/s1))
}
