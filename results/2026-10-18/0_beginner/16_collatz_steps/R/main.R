for (start in c(1, 6, 27, 97, 871)) {
  n <- start
  steps <- 0
  peak <- start
  while (n != 1) {
    n <- if (n %% 2 == 0) n %/% 2 else 3 * n + 1
    steps <- steps + 1
    peak <- max(peak, n)
  }
  cat(sprintf("%d: steps=%d max=%d\n", start, steps, peak))
}
