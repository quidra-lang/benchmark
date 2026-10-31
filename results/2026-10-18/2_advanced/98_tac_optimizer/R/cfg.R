new_block <- function(number, labels, start) {
    record(number = number, labels = labels, start = start, finish = 0L, instructions = integer(), predecessors = integer(), successors = integer())
}
new_cfg <- function(function_node) {
    graph <- record(function_node = function_node, blocks = list(), instructions = list(), positions = integer(), block_of = integer(), expressions = new_table())
    pending <- character()
    first_label <- 0L
    current <- NULL
    previous_kind <- ""
    for (index in seq_along(function_node$code)) {
        line <- function_node$code[[index]]
        if (is.character(line)) {
            if (!length(pending)) first_label <- index
            pending <- c(pending, line)
            next
        }
        number <- length(graph$instructions) + 1L
        if (is.null(current) || length(pending) || previous_kind %in% c("goto", "if", "return")) {
            start <- if (length(pending)) first_label else index
            if (!is.null(current)) current$finish <- start
            current <- new_block(length(graph$blocks) + 1L, pending, start)
            graph$blocks[[current$number]] <- current
            pending <- character()
        }
        graph$instructions[[number]] <- line
        graph$positions[number] <- index
        graph$block_of[number] <- current$number
        current$instructions <- c(current$instructions, number)
        previous_kind <- line$kind
        value <- expression(line)
        if (!is.null(value)) graph$expressions[[value$key]] <- value
    }
    current$finish <- length(function_node$code) + 1L
    labels <- new_table()
    for (block in graph$blocks) for (label in block$labels) labels[[label]] <- block$number
    for (block in graph$blocks) {
        last <- graph$instructions[[tail(block$instructions, 1L)]]
        if (last$kind == "goto") block$successors <- labels[[last$name]] else if (last$kind == "if") {
            block$successors <- unique(c(block$number + 1L, labels[[last$name]]))
        } else if (last$kind != "return") block$successors <- block$number + 1L
        for (successor in block$successors) graph$blocks[[successor]]$predecessors <- c(graph$blocks[[successor]]$predecessors, block$number)
    }
    reachable <- 1L
    postorder <- integer()
    stack <- list(c(1L, 1L))
    while (length(stack)) {
        frame <- stack[[length(stack)]]
        number <- frame[1L]
        index <- frame[2L]
        successors <- graph$blocks[[number]]$successors
        if (index > length(successors)) {
            postorder <- c(postorder, number)
            stack[[length(stack)]] <- NULL
        } else {
            stack[[length(stack)]][2L] <- index + 1L
            successor <- successors[index]
            if (!successor %in% reachable) {
                reachable <- c(reachable, successor)
                stack[[length(stack) + 1L]] <- c(successor, 1L)
            }
        }
    }
    graph$reachable <- sort(reachable)
    graph$postorder <- postorder
    graph$reverse_postorder <- rev(postorder)
    graph$reachable_predecessors <- lapply(graph$blocks, function(block) intersect(block$predecessors, reachable))
    dominators <- lapply(seq_along(graph$blocks), function(number) if (number %in% reachable) graph$reachable else integer())
    dominators[[1L]] <- 1L
    repeat {
        changed <- FALSE
        for (number in graph$reverse_postorder[-1L]) {
            predecessors <- graph$reachable_predecessors[[number]]
            value <- dominators[[predecessors[1L]]]
            for (predecessor in predecessors[-1L]) value <- intersect(value, dominators[[predecessor]])
            value <- union(value, number)
            if (!setequal(value, dominators[[number]])) {
                dominators[[number]] <- value
                changed <- TRUE
            }
        }
        if (!changed) break
    }
    graph$dominators <- dominators
    immediate <- integer(length(graph$blocks))
    for (number in setdiff(graph$reachable, 1L)) {
        strict <- setdiff(dominators[[number]], number)
        immediate[number] <- strict[which.max(vapply(strict, function(parent) length(dominators[[parent]]), integer(1L)))]
    }
    graph$immediate <- immediate
    loops <- list()
    for (header in graph$reachable) {
        latches <- Filter(function(number) header %in% dominators[[number]], graph$reachable_predecessors[[header]])
        latches <- as.integer(latches)
        if (!length(latches)) next
        members <- union(header, latches)
        pending <- setdiff(latches, header)
        while (length(pending)) {
            number <- tail(pending, 1L)
            pending <- head(pending, -1L)
            for (predecessor in graph$reachable_predecessors[[number]]) {
                if (!predecessor %in% members) {
                    members <- c(members, predecessor)
                    pending <- c(pending, predecessor)
                }
            }
        }
        loops[[length(loops) + 1L]] <- record(header = header, latches = latches, blocks = sort(members), depth = 0L, exits = integer(), outside = integer())
    }
    graph$loops <- loops
    graph$depth <- vapply(seq_along(graph$blocks), function(number) sum(vapply(loops, function(loop) number %in% loop$blocks, logical(1L))), integer(1L))
    for (loop in loops) {
        loop$depth <- sum(vapply(loops, function(other) loop$header %in% other$blocks, logical(1L)))
        for (number in loop$blocks) {
            block <- graph$blocks[[number]]
            outside <- setdiff(block$successors, loop$blocks)
            loop$outside <- union(loop$outside, outside)
            if (length(outside) || graph$instructions[[tail(block$instructions, 1L)]]$kind == "return") loop$exits <- c(loop$exits, number)
        }
    }
    graph
}
