mutex_key <- function(a, b) paste(sort(c(a, b)), collapse=",")
new_mutexes <- function() new.env(hash=TRUE, parent=emptyenv())
mutex_has <- function(mutexes, a, b) exists(mutex_key(a, b), mutexes, inherits=FALSE)
mutex_count <- function(mutexes) length(ls(mutexes, all.names=TRUE))
pair_conflict <- function(facts, mutexes) {
    for (i in seq_along(facts)) if (i < length(facts)) for (j in seq.int(i+1L, length(facts))) {
        if (mutex_has(mutexes, facts[i], facts[j])) return(TRUE)
    }
    FALSE
}
graph_conflict <- function(a, b, mutexes) {
    if (any(a$delete %in% union(b$pre, b$add)) || any(b$delete %in% union(a$pre, a$add))) return(TRUE)
    for (p in a$pre) for (q in b$pre) if (mutex_has(mutexes, p, q)) return(TRUE)
    FALSE
}
new_graph_frame <- function(type, level, goals, position=1L, chosen=integer()) {
    frame <- new.env(parent=emptyenv())
    frame$type <- type
    frame$level <- level
    frame$goals <- goals
    frame$position <- position
    frame$chosen <- chosen
    frame$stage <- 0L
    frame
}
solve_graphplan <- function(actions, initial, goal, limit) {
    facts <- list(initial)
    mutexes <- list(new_mutexes())
    levels <- exclusive_levels <- achiever_levels <- list()
    memo <- new.env(hash=TRUE, parent=emptyenv())
    lines <- character()
    counts <- new.env(parent=emptyenv())
    counts$searched <- counts$memo_hits <- counts$tried <- 0L
    extract <- function(level, goals) {
        stack <- list(new_graph_frame("extract", level, goals))
        result <- NULL
        while (length(stack)) {
            frame <- stack[[length(stack)]]
            pop_frame <- function() stack <<- head(stack, -1)
            key <- paste(frame$level, state_key(frame$goals))
            if (frame$type == "extract") {
                if (frame$stage == 0L) {
                    if (frame$level == 0L) {
                        result <- list()
                        pop_frame()
                    } else if (exists(key, memo, inherits=FALSE)) {
                        counts$memo_hits <- counts$memo_hits+1L
                        result <- NULL
                        pop_frame()
                    } else {
                        counts$searched <- counts$searched+1L
                        frame$stage <- 1L
                        stack[[length(stack)+1L]] <- new_graph_frame("assign", frame$level, frame$goals)
                    }
                } else {
                    if (is.null(result)) memo[[key]] <- TRUE
                    pop_frame()
                }
                next
            }
            elements <- levels[[frame$level]]
            if (frame$stage == 0L) {
                repeat {
                    if (frame$position > length(frame$goals)) break
                    covered <- any(vapply(frame$chosen, function(i) frame$goals[frame$position] %in% elements[[i]]$add, FALSE))
                    if (!covered) break
                    frame$position <- frame$position+1L
                }
                if (frame$position > length(frame$goals)) {
                    previous <- sort(unique(unlist(lapply(frame$chosen, function(i) elements[[i]]$pre), use.names=FALSE)))
                    frame$stage <- 2L
                    stack[[length(stack)+1L]] <- new_graph_frame("extract", frame$level-1L, previous)
                } else {
                    frame$producers <- achiever_levels[[frame$level]][[as.character(frame$goals[frame$position])]]
                    frame$next_producer <- 1L
                    frame$stage <- 1L
                }
            } else if (frame$stage == 2L) {
                if (!is.null(result)) {
                    layer <- sort(vapply(Filter(function(e) !is.na(e$number), elements[frame$chosen]), function(e) e$number, 0L))
                    result[[length(result)+1L]] <- layer
                }
                pop_frame()
            } else if (frame$stage == 3L) {
                if (!is.null(result)) pop_frame() else frame$stage <- 1L
            } else {
                selected <- 0L
                while (frame$next_producer <= length(frame$producers)) {
                    i <- frame$producers[frame$next_producer]
                    frame$next_producer <- frame$next_producer+1L
                    conflict <- any(vapply(frame$chosen, function(j) mutex_has(exclusive_levels[[frame$level]], i, j), FALSE))
                    if (!conflict) {
                        selected <- i
                        break
                    }
                }
                if (selected == 0L) {
                    result <- NULL
                    pop_frame()
                } else {
                    counts$tried <- counts$tried+1L
                    frame$stage <- 3L
                    stack[[length(stack)+1L]] <- new_graph_frame("assign", frame$level,
                        frame$goals, frame$position+1L, c(frame$chosen, selected))
                }
            }
        }
        result
    }
    finish <- function(status, layers=list()) {
        list(status=status, plan=as.integer(unlist(layers, use.names=FALSE)), layers=layers, lines=lines,
            expanded=counts$searched, generated=counts$tried, memo_hits=counts$memo_hits)
    }
    for (level in 0:limit) {
        current <- facts[[level+1L]]
        current_mutexes <- mutexes[[level+1L]]
        lines <- c(lines, paste0("fact level ", level, ": facts=", length(current), " mutexes=", mutex_count(current_mutexes)))
        possible <- all(goal %in% current) && !pair_conflict(goal, current_mutexes)
        if (possible) {
            before_search <- counts$searched
            before_hits <- counts$memo_hits
            layers <- extract(level, sort(goal))
            outcome <- if (is.null(layers)) "fail" else "success"
            lines <- c(lines, paste0("extract level ", level, ": ", outcome,
                " searched=", counts$searched-before_search, " memo_hits=", counts$memo_hits-before_hits))
            if (!is.null(layers)) return(finish("solved", layers))
        } else if (level >= 1L && length(current) == length(facts[[level]]) &&
            mutex_count(current_mutexes) == mutex_count(mutexes[[level]])) return(finish("unreachable"))
        if (level == limit) return(finish("level limit"))
        elements <- Filter(function(a) all(a$pre %in% current) && !pair_conflict(a$pre, current_mutexes), actions)
        action_count <- length(elements)
        for (p in sort(current)) elements[[length(elements)+1L]] <- list(number=NA_integer_, pre=p, add=p, delete=integer())
        exclusive <- new_mutexes()
        for (i in seq_along(elements)) if (i < length(elements)) for (j in seq.int(i+1L, length(elements))) {
            if (graph_conflict(elements[[i]], elements[[j]], current_mutexes)) exclusive[[mutex_key(i, j)]] <- TRUE
        }
        lines <- c(lines, paste0("action level ", level, ": actions=", action_count,
            " noops=", length(current), " mutexes=", mutex_count(exclusive)))
        achievers <- list()
        for (i in seq_along(elements)) for (p in elements[[i]]$add) {
            key <- as.character(p)
            achievers[[key]] <- c(achievers[[key]], i)
        }
        for (key in names(achievers)) {
            producers <- achievers[[key]]
            ranks <- vapply(producers, function(i) if (is.na(elements[[i]]$number)) -1L else elements[[i]]$number, 0L)
            achievers[[key]] <- producers[order(ranks)]
        }
        following <- sort(as.integer(names(achievers)))
        following_mutexes <- new_mutexes()
        for (i in seq_along(following)) if (i < length(following)) for (j in seq.int(i+1L, length(following))) {
            p <- following[i]
            q <- following[j]
            all_exclusive <- TRUE
            for (x in achievers[[as.character(p)]]) {
                for (y in achievers[[as.character(q)]]) if (x == y || !mutex_has(exclusive, x, y)) {
                    all_exclusive <- FALSE
                    break
                }
                if (!all_exclusive) break
            }
            if (all_exclusive) following_mutexes[[mutex_key(p, q)]] <- TRUE
        }
        levels[[length(levels)+1L]] <- elements
        exclusive_levels[[length(exclusive_levels)+1L]] <- exclusive
        achiever_levels[[length(achiever_levels)+1L]] <- achievers
        facts[[length(facts)+1L]] <- following
        mutexes[[length(mutexes)+1L]] <- following_mutexes
    }
    finish("level limit")
}
