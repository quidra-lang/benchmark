for (original in c(7, 98000, 4096, 50301, 2718281, 123456789)) {
    remaining <- original
    count <- 0
    digit_sum <- 0
    reversed <- 0
    while (remaining > 0) {
        digit <- remaining %% 10
        count <- count + 1
        digit_sum <- digit_sum + digit
        reversed <- reversed * 10 + digit
        remaining <- remaining %/% 10
    }
    cat(sprintf("%d: digits=%d sum=%d reversed=%d\n", original, count, digit_sum, reversed))
}
