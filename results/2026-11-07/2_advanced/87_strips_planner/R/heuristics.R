HEURISTIC_NAMES <- c("goalcount", "hmax", "hadd", "ff", "lmcount")
INFINITY <- .Machine$integer.max
state_key <- function(state) paste0("s", paste(sort(state), collapse=","))
new_evaluator <- function(problem) {
    engine <- new.env(parent=emptyenv())
    engine$problem <- problem
    engine$achievers <- rep(list(integer()), length(problem$facts))
    for (action in problem$actions) for (fact in action$add) {
        engine$achievers[[fact+1L]] <- c(engine$achievers[[fact+1L]], action$number)
    }
    engine$cache <- new.env(hash=TRUE, parent=emptyenv())
    engine
}
cached <- function(engine, name, state, compute) {
    key <- paste(name, state_key(state))
    if (exists(key, engine$cache, inherits=FALSE)) return(engine$cache[[key]])
    value <- compute()
    engine$cache[[key]] <- value
    value
}
relaxed_costs <- function(engine, state, maximum_cost) {
    cached(engine, if (maximum_cost) "cmax" else "cadd", state, function() {
        costs <- ifelse((seq_along(engine$problem$facts)-1L) %in% state, 0L, INFINITY)
        repeat {
            changed <- FALSE
            for (action in engine$problem$actions) {
                values <- costs[action$pre+1L]
                if (INFINITY %in% values) next
                aggregate <- if (maximum_cost) max(c(0L, values)) else sum(values)
                value <- action$cost+aggregate
                for (p in action$add) if (value < costs[p+1L]) {
                    costs[p+1L] <- value
                    changed <- TRUE
                }
            }
            if (!changed) break
        }
        costs
    })
}
relaxed_plan <- function(engine, state) {
    cached(engine, "plan", state, function() {
        costs <- relaxed_costs(engine, state, FALSE)
        if (any(costs[engine$problem$goal+1L] == INFINITY)) return(NULL)
        chosen <- integer()
        pending <- sort(setdiff(engine$problem$goal, state))
        while (length(pending)) {
            fact <- tail(pending, 1)
            pending <- head(pending, -1)
            winner <- -1L
            lowest <- INFINITY
            for (number in engine$achievers[[fact+1L]]) {
                action <- engine$problem$actions[[number+1L]]
                values <- costs[action$pre+1L]
                if (INFINITY %in% values) next
                value <- action$cost+sum(values)
                if (value < lowest) {
                    winner <- number
                    lowest <- value
                }
            }
            if (!winner %in% chosen) {
                chosen <- c(chosen, winner)
                pending <- c(pending, sort(setdiff(engine$problem$actions[[winner+1L]]$pre, state)))
            }
        }
        sort(chosen)
    })
}
helpful <- function(engine, state) {
    plan <- relaxed_plan(engine, state)
    plan[vapply(plan, function(n) applicable(engine$problem$actions[[n+1L]], state), FALSE)]
}
planning_levels <- function(engine, state) {
    cached(engine, "levels", state, function() {
        facts <- ifelse((seq_along(engine$problem$facts)-1L) %in% state, 0L, INFINITY)
        actions <- rep(INFINITY, length(engine$problem$actions))
        level <- 0L
        repeat {
            changed <- FALSE
            for (action in engine$problem$actions) {
                if (actions[action$number+1L] != INFINITY || any(facts[action$pre+1L] > level)) next
                actions[action$number+1L] <- level
                for (p in action$add) if (facts[p+1L] == INFINITY) {
                    facts[p+1L] <- level+1L
                    changed <- TRUE
                }
            }
            if (!changed) return(list(facts=facts, actions=actions))
            level <- level+1L
        }
    })
}
verified_landmark <- function(engine, state, excluded) {
    reachable <- state
    repeat {
        changed <- FALSE
        for (action in engine$problem$actions) {
            if (excluded %in% action$add || !all(action$pre %in% reachable)) next
            added <- setdiff(action$add, reachable)
            if (length(added)) {
                reachable <- union(reachable, added)
                changed <- TRUE
            }
        }
        if (!changed) break
    }
    !all(engine$problem$goal %in% reachable)
}
landmarks <- function(engine, state) {
    cached(engine, "landmarks", state, function() {
        levels <- planning_levels(engine, state)
        if (any(levels$facts[engine$problem$goal+1L] == INFINITY)) return(NULL)
        selected <- setdiff(engine$problem$goal, state)
        pending <- sort(selected)
        verified <- list()
        head <- 1L
        while (head <= length(pending)) {
            fact <- pending[head]
            head <- head+1L
            numbers <- engine$achievers[[fact+1L]]
            numbers <- numbers[levels$actions[numbers+1L] == levels$facts[fact+1L]-1L]
            earliest <- lapply(numbers, function(n) engine$problem$actions[[n+1L]]$pre)
            candidates <- earliest[[1]]
            for (pre in earliest[-1]) candidates <- intersect(candidates, pre)
            for (p in sort(setdiff(candidates, union(state, selected)))) {
                key <- as.character(p)
                if (is.null(verified[[key]])) verified[[key]] <- verified_landmark(engine, state, p)
                if (verified[[key]]) {
                    selected <- union(selected, p)
                    pending <- c(pending, p)
                }
            }
        }
        sort(selected)
    })
}
heuristic_value <- function(engine, name, state) {
    if (name == "none") return(0L)
    cached(engine, name, state, function() {
        if (name == "goalcount") return(length(setdiff(engine$problem$goal, state)))
        if (name %in% c("hmax", "hadd")) {
            costs <- relaxed_costs(engine, state, name == "hmax")
            values <- costs[engine$problem$goal+1L]
            if (INFINITY %in% values) return(INFINITY)
            return(if (name == "hmax") max(c(0L, values)) else sum(values))
        }
        if (name == "ff") {
            plan <- relaxed_plan(engine, state)
            return(if (is.null(plan)) INFINITY else sum(vapply(plan, function(n) engine$problem$actions[[n+1L]]$cost, 0L)))
        }
        selected <- landmarks(engine, state)
        if (is.null(selected)) INFINITY else length(selected)
    })
}
heuristic_values <- function(engine, state) vapply(HEURISTIC_NAMES, function(name) heuristic_value(engine, name, state), 0)
