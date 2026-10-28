gene_operations <- function(instance, chromosome) {
    counts <- integer(13L)
    ids <- integer()
    for (gene in chromosome) {
        counts[gene] <- counts[gene] + 1L
        ids <- c(ids, instance$job_map[[as.character(gene)]]$operations[counts[gene]])
    }
    ids
}
decode <- function(instance, chromosome) {
    starts <- integer(length(instance$operations))
    ready <- integer(13L)
    free <- integer(instance$machine_count)
    for (id in gene_operations(instance, chromosome)) {
        op <- instance$operations[[id]]
        starts[id] <- max(ready[op$job], free[op$machine])
        ready[op$job] <- free[op$machine] <- starts[id] + op$duration
    }
    starts
}
tournament <- function(rng, values, size) {
    picks <- vapply(seq_len(size), function(i) below(rng, length(values)) + 1L, 0L)
    picks[order(values[picks], picks)[1L]]
}
crossover <- function(rng, first, second, jobs) {
    kept <- jobs[vapply(jobs, function(job) below(rng, 2L) == 0L, FALSE)]
    preserve <- function(keeper, donor) {
        fillers <- donor[!(donor %in% kept)]
        keeper[!(keeper %in% kept)] <- fillers
        keeper
    }
    list(preserve(first, second), preserve(second, first))
}
swap_mutation <- function(rng, chromosome) {
    a <- below(rng, length(chromosome)) + 1L
    b <- below(rng, length(chromosome)) + 1L
    chromosome[c(a, b)] <- chromosome[c(b, a)]
    chromosome
}
insert_mutation <- function(rng, chromosome) {
    a <- below(rng, length(chromosome)) + 1L
    b <- below(rng, length(chromosome)) + 1L
    gene <- chromosome[a]
    chromosome <- chromosome[-a]
    append(chromosome, gene, after = b - 1L)
}
