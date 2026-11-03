terms <- c(1, 1)
while (length(terms) < 30) {
  n <- length(terms)
  terms <- c(terms, terms[n - 1] + terms[n])
}
cat(paste(terms, collapse = " "), "\n", sep = "")
cat(sprintf("sum: %d\n", sum(terms)))
