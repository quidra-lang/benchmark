column_means <- function(rows) vapply(
    seq_len(ncol(rows)),
    function(j) sequential_sum(rows[,j])/nrow(rows),
    numeric(1)
)
covariance_matrix <- function(rows,means) {
  n <- nrow(rows)
  p <- ncol(rows)
  covariance <- matrix(0,p,p)
  for (j in seq_len(p)) for (k in seq.int(j,p)) {
    value <- sequential_sum((rows[,j]-means[j])*(rows[,k]-means[k]))/(n-1L)
    covariance[j,k] <- covariance[k,j] <- value
  }
  covariance
}
standard_deviations <- function(covariance) sqrt(diag(covariance))
correlation_matrix <- function(covariance,deviations) {
  p <- nrow(covariance)
  result <- matrix(0,p,p)
  for (j in seq_len(p)) for (k in seq_len(p)) result[j,k] <- if (j == k) 1 else covariance[
      j,
      k
  ]/(deviations[j]*deviations[k])
  result
}
standardize <- function(values,means,scales) ifelse(is.na(values),0,(values-means)/scales)
component_scores <- function(z,vectors) vapply(vectors,function(vector) dot_product(z,vector),numeric(1))
residuals <- function(z,scores,vectors,n) vapply(seq_along(z),function(j)
  z[j]-sequential_sum(vapply(seq_len(n),function(k) scores[k]*vectors[[k]][j],numeric(1))),numeric(1))
hotelling_t2 <- function(
    scores,
    values,
    n
) sequential_sum(scores[seq_len(n)]*scores[seq_len(n)]/values[seq_len(n)])
