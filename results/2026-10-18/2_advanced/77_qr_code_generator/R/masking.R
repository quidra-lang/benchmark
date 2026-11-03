mask_condition <- function(mask, x, y) {
    if (mask == 0L) return((x + y) %% 2L == 0L)
    if (mask == 1L) return(y %% 2L == 0L)
    if (mask == 2L) return(x %% 3L == 0L)
    if (mask == 3L) return((x + y) %% 3L == 0L)
    if (mask == 4L) return((y %/% 2L + x %/% 3L) %% 2L == 0L)
    if (mask == 5L) return((x * y) %% 2L + (x * y) %% 3L == 0L)
    if (mask == 6L) return(((x * y) %% 2L + (x * y) %% 3L) %% 2L == 0L)
    ((x + y) %% 2L + (x * y) %% 3L) %% 2L == 0L
}

apply_mask <- function(symbol, positions, mask) {
    result <- symbol
    for (index in seq_len(nrow(positions))) {
        x <- positions[index, 1L]
        y <- positions[index, 2L]
        if (mask_condition(mask, x, y)) result[y + 1L, x + 1L] <- bitwXor(result[y + 1L, x + 1L], 1L)
    }
    result
}

mask_penalties <- function(symbol) {
    side <- nrow(symbol)
    n1 <- n2 <- n3 <- 0L
    patterns <- list(
        c(1L, 0L, 1L, 1L, 1L, 0L, 1L, 0L, 0L, 0L, 0L),
        c(0L, 0L, 0L, 0L, 1L, 0L, 1L, 1L, 1L, 0L, 1L)
    )
    lines <- c(lapply(seq_len(side), function(y) symbol[y, ]), lapply(seq_len(side), function(x) symbol[, x]))
    for (line in lines) {
        run <- 1L
        for (index in 2L:side) {
            if (line[index] == line[index - 1L]) {
                run <- run + 1L
            } else {
                if (run >= 5L) n1 <- n1 + run - 2L
                run <- 1L
            }
        }
        if (run >= 5L) n1 <- n1 + run - 2L
        for (index in seq_len(side - 10L)) {
            window <- line[index:(index + 10L)]
            if (identical(window, patterns[[1L]]) || identical(window, patterns[[2L]])) n3 <- n3 + 40L
        }
    }
    for (y in seq_len(side - 1L)) for (x in seq_len(side - 1L)) {
        value <- symbol[y, x]
        if (value == symbol[y, x + 1L] && value == symbol[y + 1L, x] && value == symbol[
            y + 1L,
            x + 1L
        ]) n2 <- n2 + 3L
    }
    n4 <- 10L * (abs(20L * sum(symbol) - 10L * side * side) %/% (side * side))
    c(n1, n2, n3, n4)
}
