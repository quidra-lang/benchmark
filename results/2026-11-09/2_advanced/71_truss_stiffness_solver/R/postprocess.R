axial_forces <- function(geometry,properties,displacement,temperature,removed=0L) {
  forces <- numeric(length(geometry))
  for (number in seq_along(geometry)) {
    if (number == removed) next
    g <- geometry[[number]]
    d <- g$dofs
    extension <- (displacement[d[3L]]-displacement[d[1L]])*g$cosine+(displacement[d[4L]]-displacement[d[2L]])*g$sine
    forces[number] <- properties[[number]]$stiffness*extension-temperature[number]
  }
  forces
}
support_reactions <- function(matrix,displacement,force,restrained) {
  result <- numeric(length(force))
  for (r in restrained) {
    value <- 0
    for (d in seq_along(force)) value <- value+matrix[r,d]*displacement[d]
    result[r] <- value-force[r]
  }
  result
}
superpose <- function(combination,results) {
  term <- combination$terms[[1L]]
  keys <- c("displacement","forces","reactions","external")
  result <- lapply(results[[term$name]][keys],function(vector) term$factor*vector)
  for (term in combination$terms[-1L]) for (key in keys) {
    source <- results[[term$name]][[key]]
    for (i in seq_along(source)) result[[key]][i] <- result[[key]][i]+term$factor*source[i]
  }
  c(list(name=combination$name),result)
}
equilibrium_residual <- function(result,geometry) {
  residual <- result$external+result$reactions
  for (i in seq_along(geometry)) {
    g <- geometry[[i]]
    direction <- c(g$cosine,g$sine,-g$cosine,-g$sine)
    for (j in seq_len(4L)) residual[g$dofs[j]] <- residual[g$dofs[j]]+result$forces[i]*direction[j]
  }
  max(abs(residual))
}
