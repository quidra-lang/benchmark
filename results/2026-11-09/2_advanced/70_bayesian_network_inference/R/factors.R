entry_count <- function(variables,sizes) prod(sizes[variables])
canonical_assignment <- function(index,variables,sizes) {
  assignment <- integer(length(sizes))
  for (v in rev(variables)) {
    assignment[v] <- as.integer(index %% sizes[v])+1L
    index <- index %/% sizes[v]
  }
  assignment
}
assignments <- function(variables,sizes) lapply(
    seq_len(entry_count(variables,sizes))-1L,
    canonical_assignment,
    variables=variables,
    sizes=sizes
)
new_factor <- function(variables,entries) list(variables=variables,entries=entries)
factor_value <- function(factor,assignment,sizes) factor$entries[parent_row(
    factor$variables,
    assignment,
    sizes
)]
reduce_factor <- function(factor,evidence,sizes) {
  variables <- setdiff(factor$variables,evidence$variables)
  entries <- vapply(assignments(variables,sizes),function(a) {
    a[evidence$variables] <- evidence$states
    factor_value(factor,a,sizes)
  },numeric(1))
  new_factor(variables,entries)
}
product_factor <- function(left,right,sizes) {
  variables <- sort(union(left$variables,right$variables))
  entries <- vapply(
      assignments(variables,sizes),
      function(a) factor_value(left,a,sizes)*factor_value(right,a,sizes),
      numeric(1)
  )
  new_factor(variables,entries)
}
eliminate_factor <- function(factor,v,sizes,maximize=FALSE) {
  variables <- setdiff(factor$variables,v)
  entries <- vapply(assignments(variables,sizes),function(a) {
    candidates <- vapply(seq_len(sizes[v]),function(s) {
      a[v] <- s
      factor_value(factor,a,sizes)
    },numeric(1))
    if (maximize) max(candidates) else ordered_total(candidates)
  },numeric(1))
  new_factor(variables,entries)
}
cpt_factor <- function(v,parents,cpt,sizes) {
  variables <- sort(c(v,parents))
  new_factor(
      variables,
      vapply(assignments(variables,sizes),function(a) cpt[parent_row(parents,a,sizes),a[v]],numeric(1))
  )
}
multiply_factors <- function(factors,sizes) {
  if (!length(factors)) return(new_factor(integer(),1))
  result <- factors[[1L]]
  for (factor in factors[-1L]) result <- product_factor(result,factor,sizes)
  result
}
