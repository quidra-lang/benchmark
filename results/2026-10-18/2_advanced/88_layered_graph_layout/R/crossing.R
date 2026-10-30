positions <- function(orders) {
    result <- integer(sum(lengths(orders)))
    for (layer in orders) result[layer] <- seq_along(layer)-1L
    result
}
accumulator <- function(segments, position, lower_size) {
    capacity <- 1L
    while (capacity < lower_size) capacity <- capacity*2L
    tree <- integer(2L*capacity-1L)
    total <- 0L
    upper <- vapply(segments, function(s) position[s[1]], 0L)
    lower <- vapply(segments, function(s) position[s[2]], 0L)
    for (i in order(upper, lower)) {
        index <- lower[i]+capacity
        tree[index] <- tree[index]+1L
        while (index > 1L) {
            if (index %% 2L == 0L) total <- total+tree[index+1L]
            index <- index %/% 2L
            tree[index] <- tree[index]+1L
        }
    }
    total
}
brute_crossings <- function(segments, position) {
    total <- 0L
    for (i in seq_along(segments)) if (i < length(segments)) for (j in seq.int(i+1L, length(segments))) {
        a <- segments[[i]]
        b <- segments[[j]]
        if ((position[a[1]]-position[b[1]])*(position[a[2]]-position[b[2]]) < 0L) total <- total+1L
    }
    total
}
gap_counts <- function(gaps, orders) {
    position <- positions(orders)
    vapply(seq_along(gaps), function(i) accumulator(gaps[[i]], position, length(orders[[i+1L]])), 0L)
}
total_crossings <- function(gaps, orders) sum(gap_counts(gaps, orders))
local_crossings <- function(gaps, orders, layer) {
    position <- positions(orders)
    indices <- c(layer-1L, layer)
    indices <- indices[indices >= 1L & indices <= length(gaps)]
    sum(vapply(indices, function(i) accumulator(gaps[[i]], position, length(orders[[i+1L]])), 0L))
}
adjacent_cost <- function(a, b, upper, lower, position) {
    total <- 0L
    for (neighbors in list(upper, lower)) for (u in neighbors[[a]]) for (v in neighbors[[b]]) {
        total <- total+as.integer(position[u] > position[v])
    }
    total
}
