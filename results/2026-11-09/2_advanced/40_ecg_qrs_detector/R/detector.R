find_peaks <- function(signals) {
  integrated <- signals$integrated
  band <- signals$bandpass
  derivative <- signals$derivative
  peaks <- list()
  for (i in seq_along(integrated)) {
    value <- integrated[i]
    if (value <= 0) next
    left <- seq.int(max(1L,i-20L),i)
    right <- seq.int(i,min(length(integrated),i+20L))
    if (any(integrated[left[left < i]] >= value) || any(integrated[right[right > i]] > value)) next
    candidates <- seq.int(max(1L,i-30L),i)
    r <- candidates[which.max(abs(band[candidates]))]
    peaks[[length(peaks)+1L]] <- list(time=i-1L,r=r-1L,peak_i=value,
      peak_f=abs(band[r]),slope=max(abs(derivative[seq.int(max(1L,i-29L),i)])),
      thr_i=0,thr_f=0,kind="")
  }
  peaks
}
initial_levels <- function(signals) {
  integrated <- signals$integrated[seq_len(400L)]
  band <- abs(signals$bandpass[seq_len(400L)])
  list(spki=max(integrated) %/% 3,npki=sum(integrated) %/% 800,
       spkf=max(band) %/% 3,npkf=sum(band) %/% 800)
}
width_ms <- function(band,r) {
  positions <- seq.int(max(0,r-25L),min(length(band)-1L,r+25L))
  positions <- positions[4*abs(band[positions+1L]) >= abs(band[r+1L])]
  5*(tail(positions,1L)-positions[1L]+1L)
}
