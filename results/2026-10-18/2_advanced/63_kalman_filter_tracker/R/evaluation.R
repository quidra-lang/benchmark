squared_distance <- function(a,b) {
  dx <- a[1L]-b[1L]
  dy <- a[2L]-b[2L]
  dx*dx+dy*dy
}
distance <- function(a,b) sqrt(squared_distance(a,b))
ospa <- function(first,second,cutoff) {
  if (!length(first) && !length(second)) return(0)
  if (!length(first) || !length(second)) return(cutoff)
  smaller <- if (length(first) <= length(second)) first else second
  larger <- if (length(first) <= length(second)) second else first
  costs <- matrix(0,length(smaller),length(larger))
  for (i in seq_along(smaller)) for (j in seq_along(larger)) {
    clipped <- min(cutoff,distance(smaller[[i]],larger[[j]]))
    costs[i,j] <- clipped*clipped
  }
  matches <- minimum_matching(costs)
  cost <- ordered_total(vapply(
      seq_len(nrow(matches)),
      function(i) costs[matches[i,1L],matches[i,2L]],
      numeric(1)
  ))
  sqrt((cost+cutoff*cutoff*(length(larger)-length(smaller)))/length(larger))
}
continuity <- function(labels) {
  covered <- groups <- swaps <- previous <- 0L
  previous_covered <- FALSE
  delay <- NULL
  for (index in seq_along(labels)) {
    label <- labels[index]
    if (label == 0L) {
      previous_covered <- FALSE
      next
    }
    covered <- covered+1L
    if (is.null(delay)) delay <- index-1L
    if (!previous_covered) groups <- groups+1L
    if (previous != 0L && label != previous) swaps <- swaps+1L
    previous <- label
    previous_covered <- TRUE
  }
  list(covered=covered,breaks=max(0L,groups-1L),swaps=swaps,delay=delay)
}
real_text <- function(value) {
  if (is.null(value)) return("-")
  text <- sprintf("%.4f",value)
  if (text == "-0.0000") "0.0000" else text
}
