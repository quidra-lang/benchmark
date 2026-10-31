factorials <- cumprod(c(1, 1:12))
for (n in 0:12) {
  cat(sprintf("%d! = %d\n", n, factorials[n + 1]))
}
