minimum_matching <- function(costs) {
  a <- nrow(costs)
  b <- ncol(costs)
  if (a == 0L || b == 0L) return(matrix(integer(),0L,2L))
  flipped <- a > b
  matrix <- if (flipped) t(costs) else costs
  rows <- nrow(matrix)
  columns <- ncol(matrix)
  u <- numeric(rows+1L)
  v <- numeric(columns+1L)
  matched <- previous <- integer(columns+1L)
  for (row in seq_len(rows)) {
    matched[1L] <- row
    column <- 1L
    distances <- rep(Inf,columns+1L)
    used <- rep(FALSE,columns+1L)
    repeat {
      used[column] <- TRUE
      current_row <- matched[column]
      delta <- Inf
      following <- 0L
      for (candidate in seq.int(2L,columns+1L)) {
        if (used[candidate]) next
        reduced <- matrix[current_row,candidate-1L]-u[current_row+1L]-v[candidate]
        if (reduced < distances[candidate]) {
          distances[candidate] <- reduced
          previous[candidate] <- column
        }
        if (distances[candidate] < delta) {
          delta <- distances[candidate]
          following <- candidate
        }
      }
      for (candidate in seq_len(columns+1L)) {
        if (used[candidate]) {
          u[matched[candidate]+1L] <- u[matched[candidate]+1L]+delta
          v[candidate] <- v[candidate]-delta
        } else distances[candidate] <- distances[candidate]-delta
      }
      column <- following
      if (matched[column] == 0L) break
    }
    while (column != 1L) {
      following <- previous[column]
      matched[column] <- matched[following]
      column <- following
    }
  }
  columns_used <- which(matched[-1L] != 0L)
  pairs <- cbind(matched[columns_used+1L],columns_used)
  if (flipped) pairs <- pairs[,2:1,drop=FALSE]
  pairs[order(pairs[,1L],pairs[,2L]),,drop=FALSE]
}
optimal_assignment <- function(rows,columns,usable) {
  if (rows == 0L || columns == 0L || !any(is.finite(usable))) return(matrix(integer(),0L,2L))
  penalty <- (min(rows,columns)+1L)*(max(1,usable[is.finite(usable)])+1)
  costs <- usable
  costs[!is.finite(costs)] <- penalty
  pairs <- minimum_matching(costs)
  keep <- vapply(seq_len(nrow(pairs)),function(i) is.finite(usable[pairs[i,1L],pairs[i,2L]]),logical(1))
  pairs[keep,,drop=FALSE]
}
