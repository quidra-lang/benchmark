for (n in c(0, 7, 999, 1000, -456789, 3141592, 9876543210)) {
  negative <- n < 0
  magnitude <- format(abs(n), big.mark = ",", scientific = FALSE, trim = TRUE)
  cat(if (negative) "-" else "", magnitude, "\n", sep = "")
}
