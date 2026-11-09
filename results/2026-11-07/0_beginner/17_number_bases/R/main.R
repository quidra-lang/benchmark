for (n in c(0, 10, 255, 1000, 43981, 65535)) {
  bits <- paste(rev(as.integer(intToBits(n))), collapse = "")
  binary <- sub("^0+(.)", "\\1", bits)
  cat(sprintf("%d: bin=%s oct=%o hex=%X\n", n, binary, as.integer(n), as.integer(n)))
}
