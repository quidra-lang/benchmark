associate <- function(picks,window,minimum) {
  candidates <- list()
  for (index in seq_along(picks)) {
    first <- picks[[index]]
    if (first$assigned) next
    chosen <- list()
    seen <- integer()
    for (pick in picks[seq.int(index,length(picks))]) {
      if (pick$sample > first$sample+window) break
      if (pick$assigned || pick$station %in% seen) next
      chosen[[length(chosen)+1L]] <- pick
      seen <- c(seen,pick$station)
    }
    if (length(chosen) < minimum) next
    for (pick in chosen) pick$assigned <- TRUE
    candidates[[length(candidates)+1L]] <- list(number=length(candidates)+1L,first=first,picks=chosen)
  }
  candidates
}
