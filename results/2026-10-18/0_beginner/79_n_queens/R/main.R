solve_queens <- function(n) {
  columns <- rep(-1L, n)
  first_solution <- integer(0)
  solutions <- 0
  place <- function(row) {
    if (row == n) {
      solutions <<- solutions + 1
      if (length(first_solution) == 0) first_solution <<- columns
      return(invisible(NULL))
    }
    previous <- seq_len(row)
    for (column in 0:(n - 1)) {
      if (all(columns[previous] != column & abs(columns[previous] - column) != row + 1 - previous)) {
        columns[row + 1] <<- column
        place(row + 1)
      }
    }
  }
  place(0)
  list(count = solutions, first = first_solution)
}

for (n in 4:8) {
  result <- solve_queens(n)
  cat(sprintf("N=%d: %d solutions\n", n, result$count))
}
for (column in result$first) cat(strrep(".", column), "Q", strrep(".", 7 - column), "\n", sep = "")
