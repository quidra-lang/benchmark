numbers <- c(27, 64, 13, 88, 41, 5, 72, 36)
total <- 0
for (pass in 1:7) {
  changed <- FALSE
  for (j in 1:(8 - pass)) {
    if (numbers[j] > numbers[j + 1]) {
      numbers[c(j, j + 1)] <- numbers[c(j + 1, j)]
      total <- total + 1
      changed <- TRUE
    }
  }
  cat(sprintf("pass %d: %s\n", pass, paste(numbers, collapse = " ")))
  if (!changed) break
}
cat(sprintf("swaps: %d\n", total))
