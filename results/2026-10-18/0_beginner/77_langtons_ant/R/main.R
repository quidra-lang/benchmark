board <- matrix(FALSE, 11, 11)
row <- 5
column <- 5
direction <- 0
directions <- list(c(-1, 0), c(0, 1), c(1, 0), c(0, -1))
for (step in 1:300) {
  turn <- if (board[row + 1, column + 1]) -1 else 1
  direction <- (direction + turn) %% 4
  board[row + 1, column + 1] <- !board[row + 1, column + 1]
  row <- (row + directions[[direction + 1]][1]) %% 11
  column <- (column + directions[[direction + 1]][2]) %% 11
}
for (r in 0:10) {
  line <- ifelse(board[r + 1, ], "#", ".")
  if (r == row) line[column + 1] <- "A"
  cat(paste(line, collapse = ""), "\n", sep = "")
}
cat(sprintf("black: %d\n", sum(board)))
