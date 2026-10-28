MODELS <- c("P","JC","K2P")
TRANSITIONS <- c("AG","GA","CT","TC")
pair_counts <- function(first,second,weights) {
  sites <- transitions <- transversions <- 0L
  for (i in seq_along(first)) {
    a <- first[i]
    b <- second[i]
    if (!(a %in% BASES) || !(b %in% BASES)) next
    sites <- sites+weights[i]
    if (a != b) {
      if (paste0(
          a,
          b
      ) %in% TRANSITIONS) transitions <- transitions+weights[i] else transversions <- transversions+weights[i]
    }
  }
  c(sites,transitions,transversions)
}
all_pairs <- function(sequences,weights) {
  pairs <- list()
  for (i in seq_len(length(sequences)-1L)) for (j in seq.int(
      i+1L,
      length(sequences)
  )) pairs[[length(pairs)+1L]] <- c(
      i,
      j,
      pair_counts(sequences[[i]],sequences[[j]],weights)
  )
  pairs
}
corrected <- function(model,n,s,v,replacement) {
  saturated <- n == 0L || (model == "JC" && 4L*(s+v) >= 3L*n) || (model == "K2P" && (2L*s+v >= n || 2L*v >= n))
  if (saturated) return(list(value=replacement,saturated=TRUE))
  value <- if (model == "P") (s+v)/n else if (model == "JC") -(3/4)*log(1-(4L*(s+v))/(3L*n)) else -(1/2)*log(1-(2L*s)/n-v/n)-(1/4)*log(1-(2L*v)/n)
  list(value=value,saturated=FALSE)
}
build_matrix <- function(pairs,n,model,replacement) {
  matrix <- matrix(0,n,n)
  saturated <- list()
  for (pair in pairs) {
    result <- corrected(model,pair[3L],pair[4L],pair[5L],replacement)
    matrix[pair[1L],pair[2L]] <- matrix[pair[2L],pair[1L]] <- result$value
    if (result$saturated) saturated[[length(saturated)+1L]] <- pair[1:3]
  }
  list(matrix=matrix,saturated=saturated)
}
