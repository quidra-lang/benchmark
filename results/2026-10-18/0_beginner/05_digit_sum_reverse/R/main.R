for (original in c(7, 98000, 4096, 50301, 2718281, 123456789)) {
    digits <- as.integer(strsplit(sprintf("%d", original), "", fixed = TRUE)[[1]])
    reversed <- as.integer(paste(rev(digits), collapse = ""))
    cat(sprintf("%d: digits=%d sum=%d reversed=%d\n", original, length(digits), sum(digits), reversed))
}
