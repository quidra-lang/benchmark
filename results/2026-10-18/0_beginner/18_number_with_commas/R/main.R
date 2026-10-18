for (n in c(0, 7, 999, 1000, -456789, 3141592, 9876543210)) {
    cat(format(n, big.mark = ",", scientific = FALSE, trim = TRUE), "\n", sep = "")
}
