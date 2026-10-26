matrix_values <- matrix(c(
  125, 340, 78, 912, 456,
  603, 27, 819, 150, 384,
  0, 765, 231, 498, 62,
  947, 113, 586, 39, 720
), nrow = 4, byrow = TRUE)
totals <- addmargins(matrix_values)
for (i in seq_len(nrow(totals))) {
  cat(paste(sprintf("%6d", totals[i, ]), collapse = ""), "\n", sep = "")
}
