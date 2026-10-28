median_value <- function(values) {
  ordered <- sort(values)
  n <- length(ordered)
  if (n %% 2L) ordered[n %/% 2L+1L] else (ordered[n %/% 2L]+ordered[n %/% 2L+1L])/2
}
local_maximum <- function(
    values,
    k
) k > 0L && k < length(values)-1L && values[k+1L] > values[k] && values[k+1L] > values[k+2L]
interpolate <- function(values,k,logarithmic=TRUE) {
  if (!local_maximum(values,k)) return(c(as.numeric(k),values[k+1L]))
  entries <- values[seq.int(k,k+2L)]
  if (logarithmic) entries <- log(entries)
  left <- entries[1L]
  middle <- entries[2L]
  right <- entries[3L]
  delta <- (left-right)/(2*(left-2*middle+right))
  fitted <- middle-(left-right)*delta/4
  c(k+delta,if (logarithmic) exp(fitted) else fitted)
}
amplitude_spectrum <- function(signal,name,n) {
  weights <- window(name,n)
  weighted <- signal[seq_len(n)]*weights
  transformed <- dft(weighted)
  s1 <- ordered_sum(weights)
  bins <- seq.int(0L,n %/% 2L)
  amplitudes <- ifelse(bins == 0L | 2L*bins == n,1,2)*Mod(transformed[bins+1L])/s1
  list(weighted=weighted,transformed=transformed,amplitudes=amplitudes)
}
packed_and_error <- function(samples) {
  packed <- packed_real(samples)
  reference <- radix2(samples)
  list(values=packed,error=max(Mod(packed-reference[seq_along(packed)])))
}
welch_spectra <- function(x,y,fs,n,name) {
  weights <- window(name,n)
  energy <- ordered_sum(weights*weights)
  segments <- (length(x)-n) %/% (n %/% 2L)+1L
  count <- n %/% 2L+1L
  pxx <- pyy <- numeric(count)
  pxy <- complex(count)
  packing_error <- 0
  for (block in seq_len(segments)-1L) {
    start <- block*(n %/% 2L)
    xf <- packed_and_error(x[seq.int(start+1L,start+n)]*weights)
    yf <- packed_and_error(y[seq.int(start+1L,start+n)]*weights)
    packing_error <- max(packing_error,xf$error,yf$error)
    for (k in seq_len(count)) {
      pxx[k] <- pxx[k]+Mod(xf$values[k])^2
      pyy[k] <- pyy[k]+Mod(yf$values[k])^2
      pxy[k] <- pxy[k]+Conj(xf$values[k])*yf$values[k]
    }
  }
  bins <- seq.int(0L,n %/% 2L)
  psd <- ifelse(bins == 0L | bins == n %/% 2L,1,2)*pxx/(segments*fs*energy)
  list(segments=segments,psd=psd,coherence=Mod(pxy)^2/(pxx*pyy),transfer=pxy/pxx,packing_error=packing_error)
}
spectrogram_magnitudes <- function(signal,n,hop,name) {
  weights <- window(name,n)
  frames <- (length(signal)-n) %/% hop+1L
  grid <- list()
  error <- 0
  for (t in seq_len(frames)-1L) {
    transformed <- packed_and_error(signal[seq.int(t*hop+1L,t*hop+n)]*weights)
    grid[[t+1L]] <- Mod(transformed$values)
    error <- max(error,transformed$error)
  }
  list(grid=grid,error=error)
}
