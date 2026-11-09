g_value <- function(system,field,p) {
  terms <- numeric()
  for (face in system$faces[[p]]) {
    if (face$neighbor != 0L) terms <- c(
        terms,
        face$g*field[face$neighbor]
    ) else if (!is.null(face$theta)) terms <- c(terms,face$g*face$theta)
  }
  ordered_sum(terms)+system$source_all[p]
}
iterate_steady <- function(system,initial,tolerance,maximum_iterations,method,omega=1) {
  field <- rep(initial,system$mesh$count)
  changes <- numeric()
  for (iteration in seq_len(maximum_iterations)) {
    previous <- field
    if (method == "jacobi") field <- vapply(
        seq_along(field),
        function(p) g_value(system,previous,p)/system$diagonal[p],
        numeric(1)
    ) else for (p in seq_along(field)) {
      value <- g_value(system,field,p)/system$diagonal[p]
      field[p] <- if (method == "gauss_seidel") value else field[p]+omega*(value-field[p])
    }
    change <- max(abs(field-previous))
    changes <- c(changes,change)
    if (change < tolerance) break
  }
  list(
      method=method,
      field=field,
      changes=changes,
      iterations=length(changes),
      converged=tail(changes,1L) < tolerance,
      omega=omega
  )
}
band_solve <- function(system,right_hand_sides) {
  n <- system$mesh$count
  width <- system$mesh$width
  matrix <- matrix(0,n,n)
  for (p in seq_len(n)) {
    matrix[p,p] <- system$diagonal[p]
    for (face in system$faces[[p]]) if (face$neighbor != 0L) matrix[p,face$neighbor] <- -face$g
  }
  vectors <- right_hand_sides
  for (k in seq_len(n)) {
    stop <- min(n,k+width)
    if (k == stop) next
    for (i in seq.int(k+1L,stop)) {
      factor <- matrix[i,k]/matrix[k,k]
      matrix[i,k] <- 0
      for (j in seq.int(k+1L,stop)) matrix[i,j] <- matrix[i,j]-factor*matrix[k,j]
      for (v in seq_along(vectors)) vectors[[v]][i] <- vectors[[v]][i]-factor*vectors[[v]][k]
    }
  }
  lapply(vectors,function(values) {
    field <- numeric(n)
    for (i in seq.int(n,1L)) {
      value <- values[i]
      if (i < n) for (j in seq.int(i+1L,min(n,i+width))) value <- value-matrix[i,j]*field[j]
      field[i] <- value/matrix[i,i]
    }
    field
  })
}
maximum_residual <- function(system,field,rhs) {
  largest <- 0
  for (p in seq_along(system$faces)) {
    residual <- rhs[p]
    for (face in system$faces[[p]]) if (face$neighbor != 0L) residual <- residual+face$g*field[face$neighbor]
    residual <- residual-system$diagonal[p]*field[p]
    largest <- max(largest,abs(residual))
  }
  largest
}
