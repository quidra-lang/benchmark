to_base <- function(n, base) {
    alphabet <- strsplit("0123456789ABCDEF", "", fixed = TRUE)[[1]]
    if (n == 0) return("0")
    result <- ""
    while (n > 0) {
        result <- paste0(alphabet[n %% base + 1], result)
        n <- n %/% base
    }
    result
}
for (n in c(0, 10, 255, 1000, 43981, 65535)) {
    cat(sprintf("%d: bin=%s oct=%s hex=%s\n", n, to_base(n, 2), to_base(n, 8), to_base(n, 16)))
}
