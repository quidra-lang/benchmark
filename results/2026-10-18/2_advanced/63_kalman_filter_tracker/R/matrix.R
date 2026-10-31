ordered_total <- function(values) {
  result <- 0
  for (value in values) result <- result+value
  result
}
diagonal_matrix <- function(values) diag(values,nrow=length(values),ncol=length(values))
identity_matrix <- function(n) diagonal_matrix(rep(1,n))
matrix_product <- function(a,b) {
  result <- matrix(0,nrow(a),ncol(b))
  for (i in seq_len(nrow(a))) for (j in seq_len(ncol(b))) result[i,j] <- ordered_total(a[i,]*b[,j])
  result
}
matrix_vector <- function(a,vector) vapply(
    seq_len(nrow(a)),
    function(i) ordered_total(a[i,]*vector),
    numeric(1)
)
matrix_inverse <- function(a) {
  n <- nrow(a)
  augmented <- cbind(a,identity_matrix(n))
  for (column in seq_len(n)) {
    pivot <- augmented[column,column]
    for (j in seq_len(2L*n)) augmented[column,j] <- augmented[column,j]/pivot
    for (row in seq_len(n)) {
      if (row == column) next
      factor <- augmented[row,column]
      for (j in seq_len(2L*n)) augmented[row,j] <- augmented[row,j]-factor*augmented[column,j]
    }
  }
  augmented[,seq.int(n+1L,2L*n),drop=FALSE]
}
determinant2 <- function(a) a[1L,1L]*a[2L,2L]-a[1L,2L]*a[2L,1L]
quadratic2 <- function(v,a) v[1L]*(a[1L,1L]*v[1L]+a[1L,2L]*v[2L])+v[2L]*(a[2L,1L]*v[1L]+a[2L,2L]*v[2L])
