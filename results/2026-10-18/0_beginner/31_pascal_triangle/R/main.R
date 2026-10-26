row <- 1
for (n in 0:11) {
  cat(paste(row, collapse = " "), "\n", sep = "")
  row <- c(1, head(row, -1) + tail(row, -1), 1)
}
