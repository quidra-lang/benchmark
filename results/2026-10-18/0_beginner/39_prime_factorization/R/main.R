for (original in c(84,9973,15625,1001,123456,48000,999958,999999)) {
    remaining <- original; divisor <- 2; factors <- character(0)
    while (divisor * divisor <= remaining) {
        exponent <- 0
        while (remaining %% divisor == 0) {
            remaining <- remaining %/% divisor
            exponent <- exponent + 1
        }
        if (exponent > 0) factors <- c(factors, if (exponent == 1) sprintf("%d",divisor) else sprintf("%d^%d",divisor,exponent))
        divisor <- divisor + 1
    }
    if (remaining > 1) factors <- c(factors, sprintf("%d",remaining))
    cat(sprintf("%d = %s\n", original, paste(factors, collapse = " * ")))
}
