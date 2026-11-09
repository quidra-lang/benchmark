extend_pair <- function(pair,activity,side,relation) {
  group <- pair[[side]]
  if (activity %in% group || relation(activity,activity) != "#") return(NULL)
  if (any(vapply(group,function(other) relation(activity,other) != "#",logical(1)))) return(NULL)
  if (side == 1L) {
    if (any(vapply(pair[[2L]],function(other) relation(activity,other) != "->",logical(1)))) return(NULL)
    list(sort(c(pair[[1L]],activity)),pair[[2L]])
  } else {
    if (any(vapply(pair[[1L]],function(other) relation(other,activity) != "->",logical(1)))) return(NULL)
    list(pair[[1L]],sort(c(pair[[2L]],activity)))
  }
}
pair_order <- function(pair) c(paste(pair[[1L]],collapse=","),paste(pair[[2L]],collapse=","))
triangle_counts <- function(log) {
  counts <- numeric()
  for (entry in log) if (length(entry$trace) >= 3L) for (i in seq_len(length(entry$trace)-2L)) {
    a <- entry$trace[i]
    b <- entry$trace[i+1L]
    if (a == entry$trace[i+2L] && a != b) counts <- add_count(counts,pair_key(a,b),entry$weight)
  }
  counts
}
plus_relation <- function(counts,triangles,a,b) {
  forward <- count_at(counts,a,b) > 0
  backward <- count_at(counts,b,a) > 0
  loop <- a != b && count_at(triangles,a,b) > 0 && count_at(triangles,b,a) > 0
  if (forward && (!backward || loop)) "->" else if (backward && (!forward || loop)) "<-" else if (forward && backward) "||" else "#"
}
