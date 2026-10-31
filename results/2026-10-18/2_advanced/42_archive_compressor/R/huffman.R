tree_lengths <- function(frequencies) {
  lengths <- integer(length(frequencies))
  nodes <- lapply(which(frequencies > 0),function(s) list(weight=frequencies[s],minimum=s,symbols=s))
  if (!length(nodes)) return(lengths)
  if (length(nodes) == 1L) {
    lengths[nodes[[1L]]$minimum] <- 1L
    return(lengths)
  }
  while (length(nodes) > 1L) {
    indices <- order(vapply(nodes,`[[`,numeric(1),"weight"),vapply(nodes,`[[`,integer(1),"minimum"))
    nodes <- nodes[indices]
    a <- nodes[[1L]]
    b <- nodes[[2L]]
    symbols <- c(a$symbols,b$symbols)
    lengths[symbols] <- lengths[symbols]+1L
    nodes <- c(
        nodes[-c(1L,2L)],
        list(list(weight=a$weight+b$weight,minimum=min(a$minimum,b$minimum),symbols=symbols))
    )
  }
  lengths
}
limited_lengths <- function(frequencies,maximum_length) {
  weights <- frequencies
  halvings <- 0L
  repeat {
    lengths <- tree_lengths(weights)
    if (max(lengths) <= maximum_length) return(list(lengths=lengths,halvings=halvings))
    weights <- (weights+1) %/% 2
    halvings <- halvings+1L
  }
}
canonical_codes <- function(lengths) {
  ordered <- which(lengths > 0L)
  ordered <- ordered[order(lengths[ordered],ordered)]
  codes <- numeric(length(lengths))
  code <- previous <- 0L
  for (i in seq_along(ordered)) {
    s <- ordered[i]
    if (i > 1L) code <- (code+1)*2^(lengths[s]-previous)
    codes[s] <- code
    previous <- lengths[s]
  }
  codes
}
