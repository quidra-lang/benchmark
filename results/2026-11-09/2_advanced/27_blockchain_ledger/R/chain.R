block_record <- function(block, parent, utxo, fees, source) {
    record <- new.env(parent = emptyenv())
    record$block <- block
    record$parent <- parent
    record$utxo <- utxo
    record$transaction_fees <- fees
    record$fees <- sum(fees)
    record$source <- source
    record$cumulative_work <- if (is.null(parent)) 1L else parent$cumulative_work + as.integer(16L ^ block$difficulty)
    record
}
block_reward <- function(height, initial, interval) {
    for (i in seq_len(height %/% interval)) initial <- initial %/% 2L
    initial
}
ancestor <- function(record, height) {
    while (record$block$height > height) record <- record$parent
    record
}
chain_to <- function(record) {
    records <- list()
    while (!is.null(record)) {
        records <- c(list(record), records)
        record <- record$parent
    }
    records
}
fork_point <- function(first, second) {
    height <- min(first$block$height, second$block$height)
    first <- ancestor(first, height)
    second <- ancestor(second, height)
    while (!identical(first, second)) {
        first <- first$parent
        second <- second$parent
    }
    first
}
median_time <- function(record) {
    times <- integer()
    while (!is.null(record) && length(times) < 3L) {
        times <- c(times, record$block$timestamp)
        record <- record$parent
    }
    sort(times)[(length(times) + 1L) %/% 2L]
}
required_difficulty <- function(parent, initial, interval, target) {
    height <- parent$block$height + 1L
    if (height == 1L) return(initial)
    difficulty <- parent$block$difficulty
    if (height %% interval != 0L) return(difficulty)
    span <- parent$block$timestamp - ancestor(parent, height - interval)$block$timestamp
    expected <- target * (interval - 1L)
    if (2L * span < expected) min(difficulty + 1L, 2L) else if (span > 2L * expected) max(
        difficulty - 1L,
        0L
    ) else difficulty
}
