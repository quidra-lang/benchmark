minstd <- function(seed) {
    rng <- new.env(parent = emptyenv())
    rng$state <- seed
    rng
}
draw <- function(rng) {
    value <- 48271L * (rng$state %% 44488L) - 3399L * (rng$state %/% 44488L)
    if (value <= 0L) value <- value + 2147483647L
    rng$state <- value
    value
}
below <- function(rng, limit) draw(rng) %% limit
chance <- function(rng, fraction) below(rng, fraction[2L]) < fraction[1L]
shuffle_genes <- function(rng, genes) {
    if (length(genes) > 1L) for (i in seq.int(length(genes), 2L)) {
        j <- below(rng, i) + 1L
        genes[c(i, j)] <- genes[c(j, i)]
    }
    genes
}
