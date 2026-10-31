key_pair <- function(key) strsplit(key, ":", fixed = TRUE)[[1L]]
reaching_transfer <- function(entry, number, state, graph) {
    if (is.null(entry$destination)) return(state)
    keep <- vapply(state, function(definition) key_pair(definition)[1L] != entry$destination, logical(1L))
    union(state[keep], paste0(entry$destination, ":", number))
}
live_transfer <- function(entry, state) union(setdiff(state, entry$destination), used_variables(entry))
expression_transfer <- function(entry, number, state, graph) {
    value <- expression_key(entry)
    if (!is.null(value)) state <- union(state, value)
    keep <- vapply(state, function(key) {
        expression <- graph$expressions[[key]]
        if (entry$kind == "store" && expression$kind == "load" && expression$operation == entry$name) return(FALSE)
        if (entry$kind == "call" && expression$kind == "load") return(FALSE)
        is.null(entry$destination) || !entry$destination %in% c(if (is.character(expression$a)) expression$a, if (is.character(expression$b)) expression$b)
    }, logical(1L))
    state[keep]
}
copy_transfer <- function(entry, number, state, graph) {
    if (!is.null(entry$destination)) state <- state[vapply(state, function(pair) !entry$destination %in% key_pair(pair), logical(1L))]
    if (entry$kind == "copy" && is.character(entry$a) && entry$destination != entry$a) state <- union(state, paste0(entry$destination, ":", entry$a))
    state
}
forward_flow <- function(graph, kind, transfer, universe) {
    incoming <- vector("list", length(graph$blocks))
    outgoing <- lapply(graph$blocks, function(block) universe)
    iterations <- 0L
    repeat {
        changed <- FALSE
        iterations <- iterations + 1L
        for (number in graph$reverse_postorder) {
            predecessors <- graph$reachable_predecessors[[number]]
            if (kind == "reaching") {
                state <- character()
                for (predecessor in predecessors) state <- union(state, outgoing[[predecessor]])
                if (number == 1L && length(graph$function_node$parameters)) {
                    state <- union(state, paste0(graph$function_node$parameters, ":0"))
                }
            } else if (number == 1L) state <- character() else {
                state <- outgoing[[predecessors[1L]]]
                for (predecessor in predecessors[-1L]) state <- intersect(state, outgoing[[predecessor]])
            }
            incoming[[number]] <- state
            for (instruction_number in graph$blocks[[number]]$instructions) state <- transfer(graph$instructions[[instruction_number]], instruction_number, state, graph)
            if (!setequal(state, outgoing[[number]])) {
                outgoing[[number]] <- state
                changed <- TRUE
            }
        }
        if (!changed) return(list(incoming = incoming, outgoing = outgoing, iterations = iterations))
    }
}
liveness <- function(graph) {
    incoming <- lapply(graph$blocks, function(block) character())
    outgoing <- vector("list", length(graph$blocks))
    iterations <- 0L
    repeat {
        changed <- FALSE
        iterations <- iterations + 1L
        for (number in graph$postorder) {
            state <- character()
            for (successor in graph$blocks[[number]]$successors) state <- union(state, incoming[[successor]])
            outgoing[[number]] <- state
            for (instruction_number in rev(graph$blocks[[number]]$instructions)) state <- live_transfer(graph$instructions[[instruction_number]], state)
            if (!setequal(state, incoming[[number]])) {
                incoming[[number]] <- state
                changed <- TRUE
            }
        }
        if (!changed) return(list(incoming = incoming, outgoing = outgoing, iterations = iterations))
    }
}
boundaries <- function(graph, incoming, transfer) {
    result <- vector("list", length(graph$instructions))
    for (block in graph$reachable) {
        state <- incoming[[block]]
        for (number in graph$blocks[[block]]$instructions) {
            result[[number]] <- state
            state <- transfer(graph$instructions[[number]], number, state, graph)
        }
    }
    result
}
new_dataflow <- function(graph) {
    expressions <- copies <- character()
    for (number in seq_along(graph$instructions)) {
        if (!graph$block_of[number] %in% graph$reachable) next
        entry <- graph$instructions[[number]]
        value <- expression_key(entry)
        if (!is.null(value)) expressions <- union(expressions, value)
        if (entry$kind == "copy" && is.character(entry$a) && entry$destination != entry$a) copies <- union(copies, paste0(entry$destination, ":", entry$a))
    }
    reaching <- forward_flow(graph, "reaching", reaching_transfer, character())
    live <- liveness(graph)
    expressions <- forward_flow(graph, "expressions", expression_transfer, expressions)
    copies <- forward_flow(graph, "copies", copy_transfer, copies)
    before <- after <- vector("list", length(graph$instructions))
    for (block in graph$reachable) {
        state <- live$outgoing[[block]]
        for (number in rev(graph$blocks[[block]]$instructions)) {
            after[[number]] <- state
            state <- live_transfer(graph$instructions[[number]], state)
            before[[number]] <- state
        }
    }
    list(iterations = c(reaching = reaching$iterations, liveness = live$iterations, expressions = expressions$iterations, copies = copies$iterations),
        reaching_in = reaching$incoming, reaching_out = reaching$outgoing, live_in = live$incoming, live_out = live$outgoing,
        expression_in = expressions$incoming, expression_out = expressions$outgoing, copy_in = copies$incoming, copy_out = copies$outgoing,
        reaching_before = boundaries(graph, reaching$incoming, reaching_transfer),
        expression_before = boundaries(graph, expressions$incoming, expression_transfer),
        copy_before = boundaries(graph, copies$incoming, copy_transfer), live_before = before, live_after = after)
}
