names <- c("Tanaka", "Suzuki", "Yamada", "Ito", "Kato", "Mori")
scores <- matrix(c(78, 85, 94, 88, 74, 82, 65, 90, 71, 80, 79, 85, 92, 88, 95, 70, 62, 78), nrow = 6, byrow = TRUE)
totals <- rowSums(scores)
ordered <- order(-totals, names, method = "radix")
ranks <- rank(-totals, ties.method = "min")
cat(sprintf(
  "%d. %s total=%d average=%.2f\n",
  ranks[ordered], names[ordered], totals[ordered], totals[ordered] / 3
), sep = "")
