add_edge <- function(neighbors, first, second) {
    neighbors[[first]] <- union(neighbors[[first]], second)
    neighbors[[second]] <- union(neighbors[[second]], first)
}
new_allocation <- function(function_node, graph, flow, registers) {
    nodes <- function_node$parameters
    for (number in seq_along(graph$instructions)) {
        if (!graph$block_of[number] %in% graph$reachable) next
        entry <- graph$instructions[[number]]
        nodes <- union(nodes, c(used_variables(entry), entry$destination))
    }
    nodes <- sort(nodes, method = "radix")
    neighbors <- new_table()
    partners <- new_table()
    costs <- new_table()
    for (node in nodes) {
        neighbors[[node]] <- partners[[node]] <- character()
        costs[[node]] <- gmp::as.bigz(0L)
    }
    for (block_number in graph$reachable) {
        block <- graph$blocks[[block_number]]
        state <- flow$live_out[[block_number]]
        for (number in rev(block$instructions)) {
            entry <- graph$instructions[[number]]
            destination <- entry$destination
            if (!is.null(destination)) {
                partner <- if (entry$kind == "copy") entry$a else NULL
                for (variable in state) if (variable != destination && !identical(variable, partner)) add_edge(neighbors, destination, variable)
            }
            state <- live_transfer(entry, state)
        }
        weight <- gmp::as.bigz(10L) ^ graph$depth[block_number]
        for (number in block$instructions) {
            entry <- graph$instructions[[number]]
            for (variable in c(used_variables(entry), entry$destination)) costs[[variable]] <- costs[[variable]] + weight
        }
    }
    entry <- union(flow$live_in[[1L]], function_node$parameters)
    for (parameter in function_node$parameters) {
        costs[[parameter]] <- costs[[parameter]] + 1L
        for (variable in setdiff(entry, parameter)) add_edge(neighbors, parameter, variable)
    }
    for (entry in instructions(function_node)) {
        if (entry$kind == "copy" && is.character(entry$a) && entry$destination != entry$a) {
            if (entry$destination %in% nodes) partners[[entry$destination]] <- union(partners[[entry$destination]], entry$a)
            if (entry$a %in% nodes) partners[[entry$a]] <- union(partners[[entry$a]], entry$destination)
        }
    }
    order <- character()
    potential <- list()
    remaining <- nodes
    while (length(remaining)) {
        degrees <- setNames(vapply(remaining, function(node) length(intersect(neighbors[[node]], remaining)), integer(1L)), remaining)
        simple <- remaining[degrees < registers]
        if (length(simple)) chosen <- simple[order(degrees[simple], simple, method = "radix")][1L] else {
            candidates <- sort(remaining, method = "radix")
            chosen <- candidates[1L]
            for (node in candidates[-1L]) if (costs[[node]] * degrees[[chosen]] < costs[[chosen]] * degrees[[node]]) chosen <- node
            potential[[length(potential) + 1L]] <- list(node = chosen, degree = degrees[[chosen]])
        }
        order <- c(order, chosen)
        remaining <- setdiff(remaining, chosen)
    }
    colors <- setNames(rep.int(-2L, length(nodes)), nodes)
    for (node in rev(order)) {
        occupied <- colors[neighbors[[node]]]
        free <- setdiff(seq_len(registers) - 1L, occupied)
        if (!length(free)) colors[[node]] <- -1L else {
            preferred <- intersect(colors[partners[[node]]], free)
            colors[[node]] <- min(if (length(preferred)) preferred else free)
        }
    }
    list(nodes = nodes, neighbors = neighbors, costs = costs, partners = partners, order = order,
        potential = potential, colors = colors, spills = nodes[colors < 0L])
}
