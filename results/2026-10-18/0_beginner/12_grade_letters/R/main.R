grades <- c("A", "B", "C", "D", "F")
counts <- integer(5)
for (score in c(78, 90, 100, 59, 80, 85, 89, 70, 45, 93)) {
    index <- if (score >= 90) 1 else if (score >= 80) 2 else if (score >= 70) 3 else if (score >= 60) 4 else 5
    counts[index] <- counts[index] + 1L
    cat(sprintf("%d: %s\n", score, grades[index]))
}
for (i in seq_along(grades)) cat(sprintf("%s: %d\n", grades[i], counts[i]))
