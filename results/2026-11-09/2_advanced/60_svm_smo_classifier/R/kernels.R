kernel_value <- function(kernel,first,second) {
  if (kernel$kind == "rbf") {
    e1 <- first[1L]-second[1L]
    e2 <- first[2L]-second[2L]
    return(exp(-kernel$gamma*(e1*e1+e2*e2)))
  }
  product <- first[1L]*second[1L]+first[2L]*second[2L]
  if (kernel$kind == "linear") return(product)
  factor <- kernel$gamma*product+kernel$coef0
  value <- 1
  for (unused in seq_len(kernel$degree)) value <- value*factor
  value
}
kernel_description <- function(kernel) {
  if (kernel$kind == "linear") return("linear")
  if (kernel$kind == "rbf") return(paste("rbf gamma",fixed_text(kernel$gamma)))
  paste("poly degree",kernel$degree,"gamma",fixed_text(kernel$gamma),"coef0",fixed_text(kernel$coef0))
}
kernel_matrix <- function(kernel,points) {
  matrix <- matrix(0,length(points),length(points))
  for (i in seq_along(points)) for (j in seq_along(points)) matrix[i,j] <- kernel_value(
      kernel,
      points[[i]],
      points[[j]]
  )
  matrix
}
submatrix <- function(matrix,indices) matrix[indices,indices,drop=FALSE]
