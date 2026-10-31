try_priority_order <- function(grid, agents, distances, horizon, order, budget) {
    restrictions <- new_prohibitions()
    paths <- vector("list", length(agents))
    attempts <- list()
    for (agent in order) {
        result <- low_search(
            grid,
            agents[[agent]],
            distances[[agent]],
            agents[[agent]]$start,
            0L,
            restrictions,
            horizon,
            budget
        )
        if (result$aborted) return(list(
            paths = NULL,
            attempts = attempts,
            failure = "ll_budget",
            failed_agent = 0L
        ))
        attempts[[length(attempts) + 1L]] <- list(
            agent = agent,
            path = result$path,
            expansions = result$expansions
        )
        if (is.null(result$path)) return(list(
            paths = NULL,
            attempts = attempts,
            failure = "path",
            failed_agent = agent
        ))
        paths[[agent]] <- result$path
        reserve_path(restrictions, result$path, permanent = TRUE)
    }
    list(paths = paths, attempts = attempts, failure = "", failed_agent = 0L)
}
