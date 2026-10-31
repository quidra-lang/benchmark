sequential_sum <- function(values) {
  result <- 0
  for (value in values) result <- result+value
  result
}
identity_matrix <- function(n) diag(n)
dot_product <- function(a,b) sequential_sum(a*b)
multiply <- function(matrix,vector) vapply(
    seq_len(nrow(matrix)),
    function(i) dot_product(matrix[i,],vector),
    numeric(1)
)
vector_length <- function(vector) sqrt(dot_product(vector,vector))
normalize <- function(vector) vector/vector_length(vector)
orient <- function(vector) if (vector[which.max(abs(vector))] < 0) -vector else vector
max_difference <- function(a,b) max(abs(a-b))
deflate <- function(matrix,value,vector) {
  for (i in seq_len(nrow(matrix))) for (j in seq_len(ncol(matrix))) matrix[i,j] <- matrix[
      i,
      j
  ]-value*vector[i]*vector[j]
  matrix
}
gauss_jordan <- function(matrix) {
  n <- nrow(matrix)
  augmented <- cbind(matrix,identity_matrix(n))
  determinant <- 1
  for (k in seq_len(n)) {
    pivot <- augmented[k,k]
    determinant <- determinant*pivot
    augmented[k,] <- augmented[k,]/pivot
    for (i in seq_len(n)) {
      if (i == k) next
      gamma <- augmented[i,k]
      for (h in seq_len(2L*n)) augmented[i,h] <- augmented[i,h]-gamma*augmented[k,h]
    }
  }
  list(inverse=augmented[,seq.int(n+1L,2L*n),drop=FALSE],determinant=determinant)
}
