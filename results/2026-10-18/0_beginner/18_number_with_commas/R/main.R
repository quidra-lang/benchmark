for (n in c(0, 7, 999, 1000, -456789, 3141592, 9876543210)) {
    digits <- sprintf("%.0f", abs(n))
    groups <- character(0)
    while (nchar(digits) > 3) {
        size <- nchar(digits)
        groups <- c(substr(digits, size-2, size), groups)
        digits <- substr(digits, 1, size-3)
    }
    groups <- c(digits, groups)
    cat(if (n < 0) "-" else "", paste(groups, collapse = ","), "\n", sep = "")
}
