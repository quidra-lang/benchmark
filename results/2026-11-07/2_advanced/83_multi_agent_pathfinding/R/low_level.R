new_budget <- function(limit = .Machine$integer.max) {
    budget <- new.env(parent = emptyenv())
    budget$limit <- limit
    budget$searches <- budget$expansions <- 0L
    budget
}
new_prohibitions <- function() {
    restrictions <- list(
        states = new.env(parent = emptyenv()),
        moves = new.env(parent = emptyenv()),
        permanent = new.env(parent = emptyenv())
    )
    restrictions
}
copy_prohibitions <- function(base) lapply(
    base,
    function(table) list2env(as.list(table), envir = new.env(parent = emptyenv()))
)
state_allowed <- function(restrictions, cell, time) {
    permanent <- restrictions$permanent[[as.character(cell)]]
    !exists(
        paste(cell, time),
        restrictions$states,
        inherits = FALSE
    ) && (is.null(permanent) || time < permanent)
}
action_allowed <- function(
    restrictions,
    source,
    destination,
    time
) state_allowed(restrictions, destination, time) && (source == destination || !exists(
    paste(source, destination, time),
    restrictions$moves,
    inherits = FALSE
))
arrival_allowed <- function(restrictions, goal) {
    arrival <- 0L
    for (key in ls(restrictions$states)) {
        fields <- as.integer(strsplit(key, " ", fixed = TRUE)[[1L]])
        if (fields[1L] == goal) arrival <- max(arrival, fields[2L] + 1L)
    }
    arrival
}
reserve_path <- function(restrictions, path, start_time = 0L, permanent = FALSE) {
    for (index in seq_along(path)) {
        time <- start_time + index - 1L
        restrictions$states[[paste(path[index], time)]] <- TRUE
        if (index > 1L && path[index - 1L] != path[index]) restrictions$moves[[paste(
            path[index],
            path[index - 1L],
            time
        )]] <- TRUE
    }
    if (permanent) {
        key <- as.character(tail(path, 1L))
        old <- restrictions$permanent[[key]]
        restrictions$permanent[[key]] <- if (is.null(old)) start_time + length(path) - 1L else min(
            old,
            start_time + length(path) - 1L
        )
    }
}
lex_less <- function(first, second) {
    different <- which(first != second)
    length(different) > 0L && first[different[1L]] < second[different[1L]]
}
new_heap <- function(key = identity) {
    heap <- new.env(parent = emptyenv())
    heap$items <- list()
    heap$key <- key
    heap
}
binary_push <- function(heap, item) {
    index <- length(heap$items) + 1L
    heap$items[[index]] <- item
    while (index > 1L) {
        parent <- index %/% 2L
        if (!lex_less(heap$key(heap$items[[index]]), heap$key(heap$items[[parent]]))) break
        saved <- heap$items[[parent]]
        heap$items[[parent]] <- heap$items[[index]]
        heap$items[[index]] <- saved
        index <- parent
    }
}
binary_pop <- function(heap) {
    result <- heap$items[[1L]]
    final <- tail(heap$items, 1L)[[1L]]
    heap$items <- head(heap$items, -1L)
    if (length(heap$items)) {
        heap$items[[1L]] <- final
        index <- 1L
        while (2L * index <= length(heap$items)) {
            child <- 2L * index
            if (child < length(heap$items) && lex_less(
                heap$key(heap$items[[child + 1L]]),
                heap$key(heap$items[[child]])
            )) child <- child + 1L
            if (!lex_less(heap$key(heap$items[[child]]), heap$key(heap$items[[index]]))) break
            saved <- heap$items[[index]]
            heap$items[[index]] <- heap$items[[child]]
            heap$items[[child]] <- saved
            index <- child
        }
    }
    result
}
low_search <- function(grid, agent, distances, start, t0, restrictions, tmax, budget, window = FALSE) {
    budget$searches <- budget$searches + 1L
    beginning <- budget$expansions
    arrival <- arrival_allowed(restrictions, agent$goal)
    area <- length(grid$free)
    parents <- rep(-1L, area * (tmax - t0 + 1L))
    root <- start + 1L
    parents[root] <- 0L
    heap <- new_heap()
    binary_push(heap, c(distances[start + 1L], 0L, 0L, root))
    insertion <- 0L
    while (length(heap$items)) {
        entry <- binary_pop(heap)
        state <- entry[4L]
        budget$expansions <- budget$expansions + 1L
        if (budget$expansions > budget$limit) return(list(
            path = NULL,
            expansions = budget$expansions - beginning,
            aborted = TRUE
        ))
        cell <- (state - 1L) %% area
        time <- t0 - entry[2L]
        if ((cell == agent$goal && time >= arrival) || (window && time == tmax)) {
            reversed <- integer()
            current <- state
            while (current != 0L) {
                reversed <- c(reversed, (current - 1L) %% area)
                current <- parents[current]
            }
            return(list(path = rev(reversed), expansions = budget$expansions - beginning, aborted = FALSE))
        }
        if (time == tmax) next
        for (entry in destinations(grid, cell)) {
            destination <- entry$cell
            if (distances[destination + 1L] < 0L) next
            next_time <- time + 1L
            next_state <- destination + 1L + (next_time - t0) * area
            if (parents[next_state] != -1L || !action_allowed(
                restrictions,
                cell,
                destination,
                next_time
            )) next
            insertion <- insertion + 1L
            parents[next_state] <- state
            g <- next_time - t0
            binary_push(heap, c(g + distances[destination + 1L], -g, insertion, next_state))
        }
    }
    list(path = NULL, expansions = budget$expansions - beginning, aborted = FALSE)
}
