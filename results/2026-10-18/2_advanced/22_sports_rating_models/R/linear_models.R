cholesky_solve <- function(matrix, vector) {
  size <- length(vector)
  lower <- matrix(0, size, size)
  for (i in seq_len(size)) for (j in seq_len(i)) {
    total <- 0
    for (k in seq_len(j - 1L)) total <- total + lower[i, k] * lower[j, k]
    lower[i, j] <- if (j < i) (matrix[i, j] - total) / lower[j, j] else sqrt(matrix[i, i] - total)
  }
  forward <- numeric(size)
  for (i in seq_len(size)) {
    total <- 0
    for (k in seq_len(i - 1L)) total <- total + lower[i, k] * forward[k]
    forward[i] <- (vector[i] - total) / lower[i, i]
  }
  solution <- numeric(size)
  for (i in rev(seq_len(size))) {
    total <- 0
    if (i < size) for (k in seq.int(i + 1L, size)) total <- total + lower[k, i] * solution[k]
    solution[i] <- (forward[i] - total) / lower[i, i]
  }
  solution
}
gaussian_solve <- function(matrix, vector) {
  size <- length(vector)
  for (k in seq_len(size)) {
    pivot <- k
    if (k < size) for (row in seq.int(k + 1L, size)) if (abs(matrix[row, k]) > abs(matrix[pivot, k])) pivot <- row
    saved_row <- matrix[k, ]
    matrix[k, ] <- matrix[pivot, ]
    matrix[pivot, ] <- saved_row
    saved_value <- vector[k]
    vector[k] <- vector[pivot]
    vector[pivot] <- saved_value
    if (k < size) for (i in seq.int(k + 1L, size)) {
      factor <- matrix[i, k] / matrix[k, k]
      for (j in seq.int(k, size)) matrix[i, j] <- matrix[i, j] - factor * matrix[k, j]
      vector[i] <- vector[i] - factor * vector[k]
    }
  }
  solution <- numeric(size)
  for (i in rev(seq_len(size))) {
    total <- 0
    if (i < size) for (j in seq.int(i + 1L, size)) total <- total + matrix[i, j] * solution[j]
    solution[i] <- (vector[i] - total) / matrix[i, i]
  }
  solution
}
colley_ratings <- function(count, matches) {
  matrix <- diag(2, count)
  balance <- numeric(count)
  for (match in matches) {
    i <- match$home
    j <- match$away
    matrix[i, i] <- matrix[i, i] + 1
    matrix[j, j] <- matrix[j, j] + 1
    matrix[i, j] <- matrix[i, j] - 1
    matrix[j, i] <- matrix[j, i] - 1
    if (match$margin > 0L) {
      balance[i] <- balance[i] + 1
      balance[j] <- balance[j] - 1
    } else if (match$margin < 0L) {
      balance[i] <- balance[i] - 1
      balance[j] <- balance[j] + 1
    }
  }
  cholesky_solve(matrix, 1 + balance / 2)
}
massey_ratings <- function(count, matches) {
  last <- count + 1L
  matrix <- matrix(0, last, last)
  vector <- numeric(last)
  for (match in matches) {
    i <- match$home
    j <- match$away
    margin <- match$margin
    matrix[i, i] <- matrix[i, i] + 1
    matrix[j, j] <- matrix[j, j] + 1
    matrix[i, j] <- matrix[i, j] - 1
    matrix[j, i] <- matrix[j, i] - 1
    matrix[i, last] <- matrix[i, last] + 1
    matrix[last, i] <- matrix[last, i] + 1
    matrix[j, last] <- matrix[j, last] - 1
    matrix[last, j] <- matrix[last, j] - 1
    matrix[last, last] <- matrix[last, last] + 1
    vector[i] <- vector[i] + margin
    vector[j] <- vector[j] - margin
    vector[last] <- vector[last] + margin
  }
  matrix[count, ] <- c(rep(1, count), 0)
  vector[count] <- 0
  solution <- gaussian_solve(matrix, vector)
  list(ratings = solution[seq_len(count)], home_advantage = solution[last])
}
