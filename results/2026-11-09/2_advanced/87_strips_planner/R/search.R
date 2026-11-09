applicable <- function(action, state) all(action$pre %in% state) && !any(action$neg %in% state)
apply_action <- function(action, state) sort(union(setdiff(state, action$delete), action$add))
search_result <- function(status, expanded=0L, generated=0L, plan=integer()) {
    list(status=status, expanded=expanded, generated=generated, plan=plan)
}
lex_less <- function(a, b) {
    for (i in seq_along(a)) if (a[i] != b[i]) return(a[i] < b[i])
    FALSE
}
heap_push <- function(heap, entry) {
    i <- length(heap$data)+1L
    heap$data[[i]] <- entry
    while (i > 1L) {
        parent <- i %/% 2L
        if (!lex_less(entry$key, heap$data[[parent]]$key)) break
        heap$data[[i]] <- heap$data[[parent]]
        i <- parent
    }
    heap$data[[i]] <- entry
}
heap_pop <- function(heap) {
    first <- heap$data[[1]]
    last <- heap$data[[length(heap$data)]]
    heap$data <- head(heap$data, -1)
    if (length(heap$data)) {
        i <- 1L
        while (2L*i <= length(heap$data)) {
            child <- 2L*i
            if (child < length(heap$data) && lex_less(heap$data[[child+1L]]$key, heap$data[[child]]$key)) child <- child+1L
            if (!lex_less(heap$data[[child]]$key, last$key)) break
            heap$data[[i]] <- heap$data[[child]]
            i <- child
        }
        heap$data[[i]] <- last
    }
    first
}
search_priority <- function(algorithm, g, depth, h, weight) {
    if (algorithm == "bfs") return(depth)
    if (algorithm == "ucs") return(g)
    if (algorithm == "gbfs") return(h)
    g+h*(if (algorithm == "wastar") weight else 1L)
}
best_first <- function(problem, start, algorithm, heuristic, budget, weight, engine) {
    initial_h <- heuristic_value(engine, heuristic, start)
    if (initial_h == INFINITY) return(search_result("dead end"))
    nodes <- list(list(state=start, g=0L, depth=0L, parent=0L, action=-1L))
    heap <- new.env(parent=emptyenv())
    heap$data <- list(list(key=c(search_priority(algorithm, 0L, 0L, initial_h, weight), initial_h, 0L), index=1L))
    best <- new.env(hash=TRUE, parent=emptyenv())
    best[[state_key(start)]] <- 0L
    serial <- 1L
    expanded <- generated <- 0L
    reopen <- algorithm %in% c("ucs", "astar", "wastar")
    while (length(heap$data)) {
        index <- heap_pop(heap)$index
        node <- nodes[[index]]
        if (reopen && node$g > best[[state_key(node$state)]]) next
        if (all(problem$goal %in% node$state)) {
            plan <- integer()
            while (nodes[[index]]$parent != 0L) {
                plan <- c(plan, nodes[[index]]$action)
                index <- nodes[[index]]$parent
            }
            return(search_result("solved", expanded, generated, rev(plan)))
        }
        if (expanded == budget) return(search_result("budget", expanded, generated))
        expanded <- expanded+1L
        for (action in problem$actions) {
            if (!applicable(action, node$state)) next
            state <- apply_action(action, node$state)
            generated <- generated+1L
            cost <- node$g+action$cost
            key <- state_key(state)
            previous <- best[[key]]
            if (!is.null(previous) && (!reopen || previous <= cost)) next
            best[[key]] <- cost
            h <- heuristic_value(engine, heuristic, state)
            if (h == INFINITY) next
            child <- list(state=state, g=cost, depth=node$depth+1L, parent=index, action=action$number)
            nodes[[length(nodes)+1L]] <- child
            heap_push(heap, list(key=c(search_priority(algorithm, cost, child$depth, h, weight), h, serial), index=length(nodes)))
            serial <- serial+1L
        }
    }
    search_result("exhausted", expanded, generated)
}
hill_climbing <- function(problem, start, heuristic, budget, engine) {
    current <- start
    plan <- integer()
    current_h <- heuristic_value(engine, heuristic, current)
    expanded <- generated <- 0L
    if (current_h == INFINITY) return(search_result("dead end"))
    while (!all(problem$goal %in% current)) {
        queue <- list(list(state=current, path=integer()))
        visited <- new.env(hash=TRUE, parent=emptyenv())
        visited[[state_key(current)]] <- TRUE
        head <- 1L
        improved <- FALSE
        while (head <= length(queue) && !improved) {
            entry <- queue[[head]]
            head <- head+1L
            if (expanded == budget) return(search_result("budget", expanded, generated))
            expanded <- expanded+1L
            for (number in helpful(engine, entry$state)) {
                state <- apply_action(problem$actions[[number+1L]], entry$state)
                generated <- generated+1L
                key <- state_key(state)
                if (!is.null(visited[[key]])) next
                visited[[key]] <- TRUE
                h <- heuristic_value(engine, heuristic, state)
                if (h == INFINITY) next
                path <- c(entry$path, number)
                if (h < current_h) {
                    plan <- c(plan, path)
                    current <- state
                    current_h <- h
                    improved <- TRUE
                    break
                }
                queue[[length(queue)+1L]] <- list(state=state, path=path)
            }
        }
        if (!improved) return(search_result("stuck", expanded, generated))
    }
    search_result("solved", expanded, generated, plan)
}
run_search <- function(problem, start, algorithm, heuristic, budget, weight, engine) {
    if (algorithm == "ehc") hill_climbing(problem, start, heuristic, budget, engine) else {
        best_first(problem, start, algorithm, heuristic, budget, weight, engine)
    }
}
