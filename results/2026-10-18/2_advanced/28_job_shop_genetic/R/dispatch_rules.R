giffler_thompson <- function(instance, rule, positions = NULL) {
    starts <- integer(length(instance$operations))
    next_index <- rep(1L, 13L)
    ready <- integer(13L)
    free <- integer(instance$machine_count)
    decisions <- ties <- 0L
    for (step in seq_along(starts)) {
        candidates <- list()
        for (job in instance$jobs) if (next_index[job$number] <= length(job$operations)) {
            id <- job$operations[next_index[job$number]]
            op <- instance$operations[[id]]
            candidates <- c(candidates, list(list(id = id, start = max(ready[op$job], free[op$machine]))))
        }
        cutoff <- min(vapply(
            candidates,
            function(item) item$start + instance$operations[[item$id]]$duration,
            0L
        ))
        selected <- Filter(
            function(item) item$start + instance$operations[[item$id]]$duration == cutoff,
            candidates
        )
        machine <- min(vapply(selected, function(item) instance$operations[[item$id]]$machine, 0L))
        conflict <- Filter(
            function(item) instance$operations[[item$id]]$machine == machine && item$start < cutoff,
            candidates
        )
        priority <- function(item) {
            op <- instance$operations[[item$id]]
            switch(
                rule,
                SPT = op$duration,
                LPT = -op$duration,
                MWKR = -op$duration - op$tail,
                FIFO = ready[op$job],
                GENES = positions[item$id]
            )
        }
        values <- vapply(conflict, priority, 0L)
        lowest <- min(values)
        decisions <- decisions + as.integer(length(conflict) > 1L)
        ties <- ties + as.integer(sum(values == lowest) > 1L)
        item <- conflict[[which.min(values)]]
        op <- instance$operations[[item$id]]
        starts[item$id] <- item$start
        ready[op$job] <- free[machine] <- item$start + op$duration
        next_index[op$job] <- next_index[op$job] + 1L
    }
    list(starts = starts, decisions = decisions, ties = ties)
}
