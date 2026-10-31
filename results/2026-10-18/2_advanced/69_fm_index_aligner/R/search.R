lower_bounds <- function(sequence,reverse_index) {
  lower <- 0L
  upper <- reverse_index$size
  mismatches <- 0L
  bounds <- integer()
  for (base in sequence) {
    interval <- extend_interval(reverse_index,lower,upper,base)
    lower <- interval[1L]
    upper <- interval[2L]
    if (lower >= upper) {
      mismatches <- mismatches+1L
      lower <- 0L
      upper <- reverse_index$size
    }
    bounds <- c(bounds,mismatches)
  }
  bounds
}
backtrack <- function(sequence,maximum,forward_index,reverse_index) {
  bounds <- lower_bounds(sequence,reverse_index)
  stack <- list(c(length(sequence)-1L,maximum,0L,forward_index$size))
  nodes <- 0L
  leaves <- list()
  while (length(stack)) {
    state <- stack[[length(stack)]]
    stack <- head(stack,-1L)
    position <- state[1L]
    remaining <- state[2L]
    lower <- state[3L]
    upper <- state[4L]
    nodes <- nodes+1L
    if (remaining < if (position >= 0L) bounds[position+1L] else 0L) next
    if (position == -1L) {
      leaves[[length(leaves)+1L]] <- c(lower,upper,maximum-remaining)
      next
    }
    for (base in c("T","G","C","A")) {
      interval <- extend_interval(forward_index,lower,upper,base)
      if (interval[1L] >= interval[2L]) next
      mismatch <- base != sequence[position+1L]
      if (!mismatch || remaining >= 1L) stack[[length(stack)+1L]] <- c(
          position-1L,
          remaining-as.integer(mismatch),
          interval
      )
    }
  }
  list(nodes=nodes,leaves=leaves,positions=sum(vapply(leaves,function(leaf) leaf[2L]-leaf[1L],integer(1))))
}
