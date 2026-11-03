root <- function(p,q) {
  target <- (40000*p) %/% q
  low <- 0
  high <- min(target+1,1048577)
  while (low+1 < high) {
    middle <- (low+high) %/% 2
    if (middle*middle <= target) low <- middle else high <- middle
  }
  (low+1) %/% 2
}
consecutive_ranges <- function(indices) {
  result <- list()
  for (index in indices) {
    n <- length(result)
    if (n > 0L && index == result[[n]][2L]+1L) {
      result[[n]][2L] <- index
    } else result[[n+1L]] <- c(index,index)
  }
  result
}
rr_statistics <- function(values) {
  if (!length(values)) return(list(mean_rr=NULL,mean_hr=NULL))
  list(mean_rr=rdiv(100*sum(values),length(values)),mean_hr=rdiv(6000000*length(values),sum(values)))
}
nn_statistics <- function(intervals,pairs) {
  e <- length(intervals)
  k <- length(pairs)
  differences <- vapply(pairs,function(pair) pair[2L]-pair[1L],numeric(1))
  totals <- vapply(pairs,sum,numeric(1))
  variance <- k*sum(differences^2)-sum(differences)^2
  histogram <- table(integer_text((16*intervals) %/% 125))
  maximum <- if (e) max(histogram) else 0
  nn50 <- sum(abs(differences) > 50)
  list(e=e,k=k,mean_nn=if (e) rdiv(100*sum(intervals),e) else NULL,
    sdnn=if (e >= 2L) root(e*sum(intervals^2)-sum(intervals)^2,e*(e-1)) else NULL,
    rmssd=if (k) root(sum(differences^2),k) else NULL,
    sdsd=if (k >= 2L) root(variance,k*(k-1)) else NULL,nn50=nn50,
    pnn50=if (k) rdiv(10000*nn50,k) else NULL,
    sd1=if (k >= 2L) root(variance,2*k*(k-1)) else NULL,
    sd2=if (k >= 2L) root(k*sum(totals^2)-sum(totals)^2,2*k*(k-1)) else NULL,
    histogram=histogram,max_count=maximum,
    triangular_index=if (e) rdiv(100*e,maximum) else NULL)
}
