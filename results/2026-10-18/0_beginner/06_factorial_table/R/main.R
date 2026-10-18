value <- 1
for (n in 0:12) {
    if (n > 0) value <- value * n
    cat(sprintf("%d! = %d\n", n, value))
}
