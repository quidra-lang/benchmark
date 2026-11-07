terms <- c(1, 1)
while (length(terms) < 30) {
  n <- length(terms)
  terms <- c(terms, terms[n - 1] + terms[n])
}
cat(paste(terms, collapse = " "), "\n", sep = "")
total <- sum(terms)
cat(sprintf("sum: %d\n", total))
