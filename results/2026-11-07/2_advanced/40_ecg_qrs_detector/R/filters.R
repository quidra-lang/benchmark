filter_ecg <- function(ecg) {
  n <- length(ecg)
  c <- low <- band <- derivative <- squared <- integrated <- numeric(n)
  at <- function(values,index) if (index >= 1L) values[index] else 0
  high_sum <- window_sum <- 0
  for (i in seq_len(n)) {
    c[i] <- 2*at(c,i-1L)-at(c,i-2L)+ecg[i]-2*at(ecg,i-6L)+at(ecg,i-12L)
    low[i] <- c[i] %/% 32
    high_sum <- high_sum+low[i]-at(low,i-32L)
    band[i] <- at(low,i-16L)-high_sum %/% 32
    derivative[i] <- (2*band[i]+at(band,i-1L)-at(band,i-3L)-2*at(band,i-4L)) %/% 8
    squared[i] <- derivative[i]^2
    window_sum <- window_sum+squared[i]-at(squared,i-30L)
    integrated[i] <- window_sum %/% 30
  }
  list(lowpass=low,bandpass=band,derivative=derivative,squared=squared,integrated=integrated)
}
