laplace <- function(values) {
  n <- nrow(values)
  if (n == 1) {
    return(values[1, 1])
  }
  total <- 0L
  for (j in seq_len(n)) {
    term <- values[1, j] * laplace(values[-1, -j, drop = FALSE])
    total <- total + if (j %% 2 == 1) term else -term
  }
  total
}

matrices <- list(
  matrix(as.integer(c(2, -3, 1, 5, 4, -2, -1, 6, 3)), nrow = 3, byrow = TRUE),
  matrix(as.integer(c(3, 0, -2, 5, 1, 4, 7, -3, -6, 2, 1, 8, 9, -5, 3, 2)), nrow = 4, byrow = TRUE),
  matrix(
    as.integer(c(4, -1, 7, 0, -3, 2, 8, -5, 6, 1, -9, 3, 2, -4, 5, 6, 0, -7, 3, -2, 1, -6, 4, 9, 8)),
    nrow = 5, byrow = TRUE
  )
)
for (values in matrices) cat(sprintf("det(%dx%d) = %d\n", nrow(values), nrow(values), laplace(values)))
