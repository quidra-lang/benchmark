path_position <- function(path, time) path[min(time + 1L, length(path))]
plan_conflicts <- function(paths) {
    horizon <- max(lengths(paths) - 1L)
    result <- list()
    if (horizon > 0L) for (time in seq_len(horizon)) for (a in seq_along(paths)) {
        if (a >= length(paths)) next
        for (b in seq.int(a + 1L, length(paths))) {
            current_a <- path_position(paths[[a]], time)
            current_b <- path_position(paths[[b]], time)
            if (current_a == current_b) {
                result[[length(result) + 1L]] <- list(
                    kind = "vertex",
                    time = time,
                    a = a,
                    b = b,
                    u = current_a,
                    v = current_a
                )
            } else if (current_a == path_position(paths[[b]], time - 1L) && current_b == path_position(
                paths[[a]],
                time - 1L
            )) {
                result[[length(result) + 1L]] <- list(
                    kind = "edge",
                    time = time,
                    a = a,
                    b = b,
                    u = path_position(paths[[a]], time - 1L),
                    v = current_a
                )
            }
        }
    }
    result
}
split_constraints <- function(conflict) {
    list(
        list(agent = conflict$a, kind = conflict$kind, u = conflict$u, v = conflict$v, time = conflict$time),
        list(agent = conflict$b, kind = conflict$kind, u = conflict$v, v = conflict$u, time = conflict$time)
    )
}
plan_cost <- function(
    paths,
    cost_function
) if (cost_function == "SOC") sum(lengths(paths) - 1L) else max(lengths(paths) - 1L)
new_node <- function(paths, constraints, number, depth, parent, cost_function) list(
    paths = paths,
    constraints = constraints,
    number = number,
    depth = depth,
    parent = parent,
    conflicts = plan_conflicts(paths),
    cost = plan_cost(paths, cost_function)
)
node_key <- function(node) c(node$cost, length(node$conflicts), node$number)
ordered_constraints <- function(node, grid) {
    result <- list()
    for (agent in seq_along(node$constraints)) {
        restrictions <- node$constraints[[agent]]
        for (key in ls(restrictions$states)) {
            fields <- as.integer(strsplit(key, " ", fixed = TRUE)[[1L]])
            result[[length(result) + 1L]] <- list(
                agent = agent,
                time = fields[2L],
                rank = 0L,
                u = fields[1L],
                v = fields[1L],
                kind = "vertex"
            )
        }
        for (key in ls(restrictions$moves)) {
            fields <- as.integer(strsplit(key, " ", fixed = TRUE)[[1L]])
            result[[length(result) + 1L]] <- list(
                agent = agent,
                time = fields[3L],
                rank = 1L,
                u = fields[1L],
                v = fields[2L],
                kind = "edge"
            )
        }
    }
    if (!length(result)) return(result)
    result[order(
        vapply(result, function(item) item$agent, 0L),
        vapply(result, function(item) item$time, 0L),
        vapply(result, function(item) item$rank, 0L),
        vapply(result, function(item) item$u %% grid$width, 0L),
        vapply(result, function(item) item$u %/% grid$width, 0L),
        vapply(result, function(item) item$v %% grid$width, 0L),
        vapply(result, function(item) item$v %/% grid$width, 0L)
    )]
}
