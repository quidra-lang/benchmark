source("grid_map.R")
source("low_level.R")
source("cbs.R")
source("prioritized.R")
source("report.R")

CONFLICT_CLASSES <- c("cardinal", "semi_cardinal", "non_cardinal")

read_parameters <- function(agent_count) {
    settings <- list(orders = list(seq_len(agent_count)), runs = list(), delays = list())
    for (line in readLines("input/params.txt", warn = FALSE)) {
        fields <- strsplit(line, " ", fixed = TRUE)[[1L]]
        kind <- fields[1L]
        arguments <- fields[-1L]
        if (kind %in% c("HORIZON", "HL_BUDGET", "LL_BUDGET")) {
            settings[[tolower(kind)]] <- as.integer(arguments[1L])
        } else if (kind == "WINDOW") {
            settings$window <- as.integer(arguments[1L])
            settings$step <- as.integer(arguments[2L])
        } else if (kind == "ORDER") {
            settings$orders[[length(settings$orders) + 1L]] <- as.integer(arguments) + 1L
        } else if (kind == "RUN") {
            settings$runs[[length(settings$runs) + 1L]] <- list(
                name = paste(arguments, collapse = "-"),
                solver = arguments[1L],
                cost_function = arguments[2L]
            )
        } else if (kind == "ANIMATE") {
            settings$animate <- arguments[1L]
            settings$frames <- as.integer(arguments[2L])
        } else {
            values <- as.integer(arguments)
            settings$delays[[length(settings$delays) + 1L]] <- c(values[1L] + 1L, values[2:3])
        }
    }
    settings
}

grid_statistics <- function(grid) {
    free_cells <- which(grid$free) - 1L
    degrees <- vapply(free_cells, function(cell) length(grid_neighbors(grid, cell)), 0L)
    remaining <- grid$free
    components <- 0L
    while (any(remaining)) {
        components <- components + 1L
        seed <- which(remaining)[1L] - 1L
        remaining[seed + 1L] <- FALSE
        queue <- seed
        index <- 1L
        while (index <= length(queue)) {
            cell <- queue[index]
            index <- index + 1L
            for (other in grid_neighbors(grid, cell)) {
                if (remaining[other + 1L]) {
                    remaining[other + 1L] <- FALSE
                    queue <- c(queue, other)
                }
            }
        }
    }
    list(
        isolated = sum(degrees == 0L),
        dead_ends = sum(degrees == 1L),
        corridors = sum(degrees == 2L),
        junctions = sum(degrees >= 3L),
        components = components
    )
}

mdd_layers <- function(grid, agent, distances, span, restrictions) {
    layers <- rep(list(integer()), span + 1L)
    layers[[1L]] <- agent$start
    if (span > 0L) for (time in seq_len(span)) {
        next_layer <- integer()
        for (cell in layers[[time]]) for (entry in destinations(grid, cell)) {
            destination <- entry$cell
            if (distances[destination + 1L] >= 0L && time + distances[destination + 1L] <= span && action_allowed(
                restrictions,
                cell,
                destination,
                time
            )) next_layer <- union(next_layer, destination)
        }
        layers[[time + 1L]] <- next_layer
    }
    valid <- rep(list(integer()), span + 1L)
    valid[[span + 1L]] <- agent$goal
    if (span > 0L) for (time in seq.int(span - 1L, 0L)) {
        valid[[time + 1L]] <- Filter(function(source) {
            any(vapply(
                destinations(grid, source),
                function(entry) entry$cell %in% valid[[time + 2L]] && action_allowed(
                    restrictions,
                    source,
                    entry$cell,
                    time + 1L
                ),
                FALSE
            ))
        }, layers[[time + 1L]])
    }
    valid
}

conflict_class <- function(conflict, paths, restrictions, grid, agents, distances, cache) {
    fixed <- logical()
    for (agent in c(conflict$a, conflict$b)) {
        span <- length(paths[[agent]]) - 1L
        key <- as.character(agent)
        if (!exists(key, cache, inherits = FALSE)) cache[[key]] <- mdd_layers(
            grid,
            agents[[agent]],
            distances[[agent]],
            span,
            restrictions[[agent]]
        )
        layers <- cache[[key]]
        time <- conflict$time
        forced <- if (time > span) TRUE else if (conflict$kind == "vertex") length(layers[[time + 1L]]) == 1L else length(layers[[time]]) == 1L && length(layers[[time + 1L]]) == 1L
        fixed <- c(fixed, forced)
    }
    if (all(fixed)) "cardinal" else if (any(fixed)) "semi_cardinal" else "non_cardinal"
}

independent_plan <- function(grid, agents, distances, horizon) {
    budget <- new_budget()
    restrictions <- new_prohibitions()
    lapply(
        seq_along(agents),
        function(index) low_search(
            grid,
            agents[[index]],
            distances[[index]],
            agents[[index]]$start,
            0L,
            restrictions,
            horizon,
            budget
        )$path
    )
}

conflict_groups <- function(conflicts, agent_count) {
    adjacent <- rep(list(integer()), agent_count)
    for (conflict in conflicts) {
        adjacent[[conflict$a]] <- union(adjacent[[conflict$a]], conflict$b)
        adjacent[[conflict$b]] <- union(adjacent[[conflict$b]], conflict$a)
    }
    seen <- rep(FALSE, agent_count)
    result <- character()
    for (start in seq_len(agent_count)) {
        if (seen[start] || !length(adjacent[[start]])) next
        component <- start
        index <- 1L
        seen[start] <- TRUE
        while (index <= length(component)) {
            current <- component[index]
            index <- index + 1L
            for (other in sort(adjacent[[current]])) {
                if (!seen[other]) {
                    seen[other] <- TRUE
                    component <- c(component, other)
                }
            }
        }
        result <- c(result, paste0(vapply(sort(component), agent_name, ""), collapse = ""))
    }
    result
}

instance_overview <- function(grid, agents, distances, independent) {
    restrictions <- lapply(agents, function(agent) new_prohibitions())
    info <- lapply(seq_along(agents), function(index) {
        shortest <- distances[[index]][agents[[index]]$start + 1L]
        layers <- mdd_layers(grid, agents[[index]], distances[[index]], shortest, restrictions[[index]])
        list(shortest = shortest, mdd_states = sum(lengths(layers)), mdd_width = max(lengths(layers)))
    })
    cache <- new.env(parent = emptyenv())
    conflicts <- lapply(plan_conflicts(independent), function(conflict) {
        conflict$classification <- conflict_class(
            conflict,
            independent,
            restrictions,
            grid,
            agents,
            distances,
            cache
        )
        conflict
    })
    list(
        degrees = grid_statistics(grid),
        agents = info,
        soc_lower = sum(vapply(info, function(item) item$shortest, 0L)),
        makespan_lower = max(vapply(info, function(item) item$shortest, 0L)),
        conflicts = conflicts,
        groups = conflict_groups(conflicts, length(agents))
    )
}

new_run <- function(definition, settings) {
    run <- new.env(parent = emptyenv())
    run$name <- definition$name
    run$solver <- definition$solver
    run$cost_function <- definition$cost_function
    run$status <- "FAIL"
    run$reason <- ""
    run$paths <- NULL
    run$high_level <- 0L
    run$generated <- -1L
    run$budget <- new_budget(settings$ll_budget)
    run$specific <- run$trace <- character()
    run$ending <- ""
    run$metrics <- run$validation <- run$execution <- NULL
    run
}

solve_pp <- function(run, grid, agents, distances, settings) {
    for (order_number in seq_along(settings$orders)) {
        order <- settings$orders[[order_number]]
        run$high_level <- run$high_level + 1L
        before <- run$budget$expansions
        result <- try_priority_order(grid, agents, distances, settings$horizon, order, run$budget)
        for (attempt in result$attempts) {
            prefix <- sprintf("order %d agent %s", order_number, agent_name(attempt$agent))
            detail <- if (is.null(attempt$path)) "failed" else paste("cost", length(attempt$path) - 1L)
            run$trace <- c(run$trace, sprintf("%s %s expansions %d", prefix, detail, attempt$expansions))
        }
        if (result$failure == "ll_budget") {
            run$reason <- "ll_budget"
            break
        }
        planned <- length(result$attempts) - as.integer(nzchar(result$failure))
        summary <- sprintf(
            "order %d %s planned %d expansions %d",
            order_number,
            paste0(vapply(order, agent_name, ""), collapse = ""),
            planned,
            run$budget$expansions - before
        )
        if (!nzchar(result$failure)) {
            run$specific <- c(run$specific, paste(summary, "ok"))
            run$paths <- result$paths
            run$status <- "OK"
            run$ending <- paste("end OK order", order_number)
            return(invisible(NULL))
        }
        run$specific <- c(run$specific, paste(summary, "failed", agent_name(result$failed_agent)))
    }
    if (!nzchar(run$reason)) run$reason <- "orders"
    run$ending <- paste("end FAIL", run$reason)
}

apply_constraint <- function(base, addition) {
    copied <- base
    changed <- copy_prohibitions(base[[addition$agent]])
    if (addition$kind == "vertex") changed$states[[paste(
        addition$u,
        addition$time
    )]] <- TRUE else changed$moves[[paste(
        addition$u,
        addition$v,
        addition$time
    )]] <- TRUE
    copied[[addition$agent]] <- changed
    copied
}

choose_split <- function(node, run, grid, agents, distances) {
    if (run$solver == "CBS") return(list(conflict = node$conflicts[[1L]], category = ""))
    cache <- new.env(parent = emptyenv())
    classes <- vapply(
        node$conflicts,
        function(conflict) conflict_class(
            conflict,
            node$paths,
            node$constraints,
            grid,
            agents,
            distances,
            cache
        ),
        ""
    )
    index <- which.min(match(classes, CONFLICT_CLASSES))
    list(conflict = node$conflicts[[index]], category = classes[index])
}

solve_cbs <- function(run, grid, agents, distances, settings) {
    empty <- lapply(agents, function(agent) new_prohibitions())
    paths <- list()
    for (index in seq_along(agents)) {
        result <- low_search(
            grid,
            agents[[index]],
            distances[[index]],
            agents[[index]]$start,
            0L,
            empty[[index]],
            settings$horizon,
            run$budget
        )
        if (result$aborted) {
            run$reason <- "ll_budget"
            run$generated <- 0L
            run$specific <- "search expanded 0 generated 0 pruned 0 open 0"
            if (run$solver == "ICBS") run$specific <- c(
                run$specific,
                "classes cardinal 0 semi_cardinal 0 non_cardinal 0"
            )
            run$ending <- "end FAIL ll_budget"
            return(invisible(NULL))
        }
        paths[[index]] <- result$path
    }
    root <- new_node(paths, empty, 0L, 0L, -1L, run$cost_function)
    open <- new_heap(node_key)
    binary_push(open, root)
    generated <- 1L
    expanded <- pruned <- 0L
    classes <- setNames(integer(3L), CONFLICT_CLASSES)
    reason <- "exhausted"
    answer <- NULL
    while (length(open$items)) {
        node <- binary_pop(open)
        if (!length(node$conflicts)) {
            answer <- node
            reason <- ""
            break
        }
        if (expanded == settings$hl_budget) {
            reason <- "hl_budget"
            break
        }
        expanded <- expanded + 1L
        chosen <- choose_split(node, run, grid, agents, distances)
        conflict <- chosen$conflict
        category <- chosen$category
        if (nzchar(category)) classes[category] <- classes[category] + 1L
        created <- character()
        aborted <- FALSE
        for (branch in split_constraints(conflict)) {
            agent <- branch$agent
            constraints <- apply_constraint(node$constraints, branch)
            result <- low_search(
                grid,
                agents[[agent]],
                distances[[agent]],
                agents[[agent]]$start,
                0L,
                constraints[[agent]],
                settings$horizon,
                run$budget
            )
            if (result$aborted) {
                aborted <- TRUE
                break
            }
            if (is.null(result$path)) {
                pruned <- pruned + 1L
                created <- c(created, "-")
                next
            }
            new_paths <- node$paths
            new_paths[[agent]] <- result$path
            child <- new_node(
                new_paths,
                constraints,
                generated,
                node$depth + 1L,
                node$number,
                run$cost_function
            )
            binary_push(open, child)
            created <- c(created, as.character(generated))
            generated <- generated + 1L
        }
        if (aborted) {
            reason <- "ll_budget"
            break
        }
        parent <- if (node$parent == -1L) "-" else as.character(node$parent)
        text <- sprintf(
            "expand %d node %d parent %s depth %d cost %d conflicts %d split %s",
            expanded,
            node$number,
            parent,
            node$depth,
            node$cost,
            length(node$conflicts),
            conflict_text(conflict, grid)
        )
        if (nzchar(category)) text <- paste(text, "class", category)
        run$trace <- c(run$trace, paste(text, "children", created[1L], created[2L]))
    }
    run$high_level <- expanded
    run$generated <- generated
    run$specific <- c(
        run$specific,
        sprintf(
            "search expanded %d generated %d pruned %d open %d",
            expanded,
            generated,
            pruned,
            length(open$items)
        )
    )
    if (run$solver == "ICBS") run$specific <- c(
        run$specific,
        sprintf(
            "classes cardinal %d semi_cardinal %d non_cardinal %d",
            classes[["cardinal"]],
            classes[["semi_cardinal"]],
            classes[["non_cardinal"]]
        )
    )
    if (is.null(answer)) {
        run$reason <- reason
        run$ending <- paste("end FAIL", reason)
        return(invisible(NULL))
    }
    run$status <- "OK"
    run$paths <- answer$paths
    run$specific <- c(run$specific, sprintf("solution node %d depth %d", answer$number, answer$depth))
    for (constraint in ordered_constraints(answer, grid)) {
        beginning <- paste(
            "constraint",
            agent_name(constraint$agent),
            constraint$kind,
            cell_text(constraint$u, grid)
        )
        if (constraint$kind == "edge") beginning <- paste(beginning, cell_text(constraint$v, grid))
        run$specific <- c(run$specific, paste(beginning, "t", constraint$time))
    }
    run$ending <- sprintf("end OK node %d cost %d", answer$number, answer$cost)
}

solve_whca <- function(run, grid, agents, distances, settings) {
    horizon <- settings$horizon
    window <- settings$window
    step <- settings$step
    current <- vapply(agents, function(agent) agent$start, 0L)
    executed <- lapply(agents, function(agent) agent$start)
    time <- rounds <- 0L
    reason <- ""
    while (!all(vapply(seq_along(agents), function(index) current[index] == agents[[index]]$goal, FALSE))) {
        if (time >= horizon) {
            reason <- "timeout"
            break
        }
        rounds <- rounds + 1L
        restrictions <- new_prohibitions()
        done <- vapply(seq_along(agents), function(index) current[index] == agents[[index]]$goal, FALSE)
        order <- c(which(!done), which(done))
        plans <- vector("list", length(agents))
        for (index in order) {
            result <- low_search(
                grid,
                agents[[index]],
                distances[[index]],
                current[index],
                time,
                restrictions,
                time + window,
                run$budget,
                window = TRUE
            )
            if (result$aborted) {
                reason <- "ll_budget"
                break
            }
            prefix <- sprintf("round %d time %d agent %s", rounds, time, agent_name(index))
            if (is.null(result$path)) {
                run$trace <- c(run$trace, sprintf("%s blocked expansions %d", prefix, result$expansions))
                reason <- "blocked"
                break
            }
            path <- c(result$path, rep(tail(result$path, 1L), window + 1L - length(result$path)))
            plans[[index]] <- path
            run$trace <- c(
                run$trace,
                sprintf("%s moves %s expansions %d", prefix, action_string(path, grid), result$expansions)
            )
            reserve_path(restrictions, path, start_time = time)
        }
        if (nzchar(reason)) break
        for (index in seq_along(agents)) {
            executed[[index]] <- c(executed[[index]], plans[[index]][2L:(step + 1L)])
            current[index] <- plans[[index]][step + 1L]
        }
        time <- time + step
    }
    run$high_level <- rounds
    run$specific <- c(run$specific, sprintf("window %d step %d rounds %d", window, step, rounds))
    if (nzchar(reason)) {
        run$reason <- reason
        run$ending <- paste("end FAIL", reason)
    } else {
        for (index in seq_along(executed)) {
            path <- executed[[index]]
            while (length(path) > 1L && tail(
                path,
                1L
            ) == agents[[index]]$goal && path[length(path) - 1L] == agents[[index]]$goal) path <- head(
                path,
                -1L
            )
            executed[[index]] <- path
        }
        run$status <- "OK"
        run$paths <- executed
        run$ending <- paste("end OK rounds", rounds)
    }
}

validate_plan <- function(paths, agents, grid) {
    start_count <- sum(vapply(
        seq_along(paths),
        function(index) paths[[index]][1L] != agents[[index]]$start,
        FALSE
    ))
    goal_count <- sum(vapply(
        seq_along(paths),
        function(index) tail(paths[[index]], 1L) != agents[[index]]$goal,
        FALSE
    ))
    illegal <- 0L
    for (path in paths) if (length(path) > 1L) for (index in 2:length(path)) {
        if (!any(vapply(
            destinations(grid, path[index - 1L]),
            function(entry) entry$cell == path[index],
            FALSE
        ))) illegal <- illegal + 1L
    }
    collisions <- plan_conflicts(paths)
    vertex <- sum(vapply(collisions, function(conflict) conflict$kind == "vertex", FALSE))
    edge <- length(collisions) - vertex
    follows <- 0L
    for (time in seq_len(max(lengths(paths) - 1L))) for (a in seq_along(paths)) {
        past_a <- path_position(paths[[a]], time - 1L)
        next_a <- path_position(paths[[a]], time)
        if (next_a == past_a) next
        for (b in seq_along(paths)) {
            if (a == b) next
            if (next_a == path_position(
                paths[[b]],
                time - 1L
            ) && path_position(paths[[b]], time) != past_a) follows <- follows + 1L
        }
    }
    list(
        verdict = if (start_count + goal_count + illegal + vertex + edge == 0L) "VALID" else "INVALID",
        start = start_count,
        goal = goal_count,
        moves = illegal,
        vertex = vertex,
        edge = edge,
        follows = follows,
        conflicts = collisions
    )
}

path_statistics <- function(path, goal, lower, grid) {
    actions <- action_string(path, grid)
    characters <- strsplit(actions, "", fixed = TRUE)[[1L]]
    moves <- characters[characters != "."]
    turns <- if (length(moves) > 1L) sum(moves[-1L] != head(moves, -1L)) else 0L
    leave <- if (length(path) > 1L) sum(head(path, -1L) == goal & path[-1L] != goal) else 0L
    list(
        cost = length(path) - 1L,
        extra = length(path) - 1L - lower,
        waits = sum(characters == "."),
        turns = turns,
        arrive = match(goal, path) - 1L,
        leave = leave,
        actions = actions
    )
}

plan_statistics <- function(paths, agents, overview, cost_function, grid) {
    lengths <- lengths(paths) - 1L
    soc <- sum(lengths)
    makespan <- max(lengths)
    cost <- if (cost_function == "SOC") soc else makespan
    lower <- if (cost_function == "SOC") overview$soc_lower else overview$makespan_lower
    per_agent <- lapply(
        seq_along(agents),
        function(index) path_statistics(
            paths[[index]],
            agents[[index]]$goal,
            overview$agents[[index]]$shortest,
            grid
        )
    )
    arrivals <- vapply(0L:makespan, function(time) sum(lengths <= time), 0L)
    traffic <- new.env(parent = emptyenv())
    cell_waits <- new.env(parent = emptyenv())
    increment <- function(table, cell) {
        key <- as.character(cell)
        old <- table[[key]]
        table[[key]] <- if (is.null(old)) 1L else old + 1L
    }
    for (path in paths) {
        for (cell in unique(path)) increment(traffic, cell)
        if (length(path) > 1L) for (index in 2:length(path)) if (path[index - 1L] == path[index]) increment(
            cell_waits,
            path[index]
        )
    }
    cells <- as.integer(ls(traffic))
    hotspots <- head(
        cells[order(
            -vapply(cells, function(cell) traffic[[as.character(cell)]], 0L),
            cells %/% grid$width,
            cells %% grid$width
        )],
        5L
    )
    totals <- function(name) sum(vapply(per_agent, function(item) item[[name]], 0L))
    list(
        soc = soc,
        makespan = makespan,
        cost = cost,
        ratio = reduced_fraction(cost, lower),
        agents = per_agent,
        sum_extra = totals("extra"),
        max_extra = max(vapply(per_agent, function(item) item$extra, 0L)),
        waits = totals("waits"),
        turns = totals("turns"),
        arrivals = arrivals,
        traffic = traffic,
        cell_waits = cell_waits,
        hotspots = hotspots
    )
}

delayed_execution <- function(paths, settings) {
    steps <- list()
    by_cell <- new.env(parent = emptyenv())
    for (agent in seq_along(paths)) {
        path <- paths[[agent]]
        entries <- list(list(time = 0L, cell = path[1L]))
        if (length(path) > 1L) for (time in seq_len(length(path) - 1L)) {
            if (path[time + 1L] != path[time]) entries[[length(entries) + 1L]] <- list(
                time = time,
                cell = path[time + 1L]
            )
        }
        steps[[agent]] <- entries
        for (index in seq_along(entries)) {
            entry <- entries[[index]]
            key <- as.character(entry$cell)
            by_cell[[key]] <- c(by_cell[[key]], list(c(agent, index - 1L, entry$time)))
        }
    }
    prerequisites <- lapply(steps, function(entries) rep(list(list()), length(entries)))
    for (agent in seq_along(steps)) {
        entries <- steps[[agent]]
        if (length(entries) > 1L) for (index in 2:length(entries)) {
            entry <- entries[[index]]
            prerequisites[[agent]][[index]] <- lapply(
                Filter(
                    function(other) other[1L] != agent && other[3L] < entry$time,
                    by_cell[[as.character(entry$cell)]]
                ),
                function(other) other[1:2]
            )
        }
    }
    progress <- finish <- integer(length(paths))
    holds <- time <- 0L
    while (any(progress < lengths(steps) - 1L)) {
        advance <- integer()
        stopped <- 0L
        for (agent in seq_along(paths)) {
            if (progress[agent] == length(steps[[agent]]) - 1L) next
            if (any(vapply(
                settings$delays,
                function(delay) delay[1L] == agent && delay[2L] <= time && time < delay[2L] + delay[3L],
                FALSE
            ))) {
                stopped <- stopped + 1L
            } else if (all(vapply(
                prerequisites[[agent]][[progress[agent] + 2L]],
                function(requirement) progress[requirement[1L]] > requirement[2L],
                FALSE
            ))) {
                advance <- c(advance, agent)
            } else {
                holds <- holds + 1L
            }
        }
        if (!length(advance) && stopped == 0L) return(list(
            deadlock = time,
            blocked = holds,
            finish = finish,
            soc = 0L,
            makespan = 0L
        ))
        for (agent in advance) {
            progress[agent] <- progress[agent] + 1L
            if (progress[agent] == length(steps[[agent]]) - 1L) finish[agent] <- time + 1L
        }
        time <- time + 1L
    }
    list(deadlock = -1L, blocked = holds, finish = finish, soc = sum(finish), makespan = max(finish))
}

instance_lines <- function(grid, agents, overview) {
    degrees <- overview$degrees
    lines <- c(
        sprintf(
            "instance width %d height %d free %d agents %d",
            grid$width,
            grid$height,
            sum(grid$free),
            length(agents)
        ),
        sprintf(
            "map isolated %d dead_ends %d corridors %d junctions %d components %d",
            degrees$isolated,
            degrees$dead_ends,
            degrees$corridors,
            degrees$junctions,
            degrees$components
        )
    )
    for (index in seq_along(agents)) {
        agent <- agents[[index]]
        info <- overview$agents[[index]]
        lines <- c(
            lines,
            sprintf(
                "agent %s start %s goal %s distance %d mdd %d width %d",
                agent$name,
                cell_text(agent$start, grid),
                cell_text(agent$goal, grid),
                info$shortest,
                info$mdd_states,
                info$mdd_width
            )
        )
    }
    lines <- c(lines, sprintf("lower_bound soc %d makespan %d", overview$soc_lower, overview$makespan_lower))
    conflicts <- overview$conflicts
    vertex <- sum(vapply(conflicts, function(conflict) conflict$kind == "vertex", FALSE))
    classes <- paste(
        vapply(
            CONFLICT_CLASSES,
            function(category) paste(
                category,
                sum(vapply(conflicts, function(conflict) conflict$classification == category, FALSE))
            ),
            ""
        ),
        collapse = " "
    )
    c(
        lines,
        sprintf(
            "independent conflicts %d vertex %d edge %d %s",
            length(conflicts),
            vertex,
            length(conflicts) - vertex,
            classes
        ),
        paste("groups", if (length(overview$groups)) paste(overview$groups, collapse = " ") else "-")
    )
}

successful_run_lines <- function(run, agents, grid) {
    metrics <- run$metrics
    execution <- run$execution
    lines <- c(
        sprintf(
            "run %s solver %s cost_function %s result OK cost %d soc %d makespan %d ratio %s",
            run$name,
            run$solver,
            run$cost_function,
            metrics$cost,
            metrics$soc,
            metrics$makespan,
            metrics$ratio
        ),
        run$specific
    )
    for (index in seq_along(agents)) {
        info <- metrics$agents[[index]]
        lines <- c(
            lines,
            sprintf(
                "agent %s cost %d extra %d waits %d turns %d arrive %d leave %d moves %s",
                agents[[index]]$name,
                info$cost,
                info$extra,
                info$waits,
                info$turns,
                info$arrive,
                info$leave,
                info$actions
            )
        )
    }
    lines <- c(
        lines,
        paste("arrivals", paste(metrics$arrivals, collapse = " ")),
        paste(
            "hotspots",
            paste(
                vapply(
                    metrics$hotspots,
                    function(cell) paste0(cell_text(cell, grid), ":", metrics$traffic[[as.character(cell)]]),
                    ""
                ),
                collapse = " "
            )
        )
    )
    if (execution$deadlock >= 0L) c(lines, paste("execution deadlock time", execution$deadlock)) else c(
        lines,
        sprintf(
            "execution soc %d makespan %d blocked %d finish %s",
            execution$soc,
            execution$makespan,
            execution$blocked,
            paste(execution$finish, collapse = " ")
        )
    )
}

solution_lines <- function(grid, agents, overview, runs) {
    lines <- instance_lines(grid, agents, overview)
    for (run in runs) {
        lines <- c(lines, "")
        if (run$status == "OK") lines <- c(lines, successful_run_lines(run, agents, grid)) else lines <- c(
            lines,
            sprintf(
                "run %s solver %s cost_function %s result FAIL reason %s",
                run$name,
                run$solver,
                run$cost_function,
                run$reason
            ),
            run$specific
        )
    }
    succeeded <- Filter(function(run) run$status == "OK", runs)
    lines <- c(
        lines,
        "",
        sprintf("summary ok %d failed %d", length(succeeded), length(runs) - length(succeeded))
    )
    if (length(succeeded)) {
        soc <- min(vapply(succeeded, function(run) run$metrics$soc, 0L))
        span <- min(vapply(succeeded, function(run) run$metrics$makespan, 0L))
        lines <- c(
            lines,
            paste(
                "best_soc",
                soc,
                paste(
                    vapply(
                        Filter(function(run) run$metrics$soc == soc, succeeded),
                        function(run) run$name,
                        ""
                    ),
                    collapse = " "
                )
            ),
            paste(
                "best_makespan",
                span,
                paste(
                    vapply(
                        Filter(function(run) run$metrics$makespan == span, succeeded),
                        function(run) run$name,
                        ""
                    ),
                    collapse = " "
                )
            )
        )
        indices <- order(
            vapply(succeeded, function(run) run$metrics$soc, 0L),
            vapply(succeeded, function(run) run$metrics$makespan, 0L),
            seq_along(succeeded)
        )
        lines <- c(
            lines,
            paste("ranking", paste(vapply(succeeded[indices], function(run) run$name, ""), collapse = " "))
        )
    }
    lines
}

stats_lines <- function(runs) {
    lines <- "run,solver,cost_function,result,reason,cost,soc,makespan,sum_extra,max_extra,waits,turns,exec_soc,exec_makespan,high_level,generated,searches,expansions"
    for (run in runs) {
        fields <- c(
            run$name,
            run$solver,
            run$cost_function,
            run$status,
            if (nzchar(run$reason)) run$reason else "-"
        )
        if (run$status == "OK") {
            metrics <- run$metrics
            execution <- run$execution
            fields <- c(
                fields,
                metrics$cost,
                metrics$soc,
                metrics$makespan,
                metrics$sum_extra,
                metrics$max_extra,
                metrics$waits,
                metrics$turns,
                if (execution$deadlock == -1L) c(execution$soc, execution$makespan) else c("-", "-")
            )
        } else {
            fields <- c(fields, rep("-", 9L))
        }
        fields <- c(
            fields,
            run$high_level,
            if (run$generated == -1L) "-" else run$generated,
            run$budget$searches,
            run$budget$expansions
        )
        lines <- c(lines, csv_line(fields))
    }
    lines
}

validation_lines <- function(runs, independent, agents, grid, overview) {
    baseline <- validate_plan(independent, agents, grid)
    baseline$conflicts <- overview$conflicts
    plans <- c(
        list(list(name = "INDEPENDENT", validation = baseline)),
        lapply(runs, function(run) list(name = run$name, validation = run$validation))
    )
    lines <- character()
    for (plan in plans) {
        name <- plan$name
        validation <- plan$validation
        if (is.null(validation)) {
            lines <- c(lines, paste("plan", name, "verdict NONE"))
            next
        }
        lines <- c(
            lines,
            sprintf(
                "plan %s verdict %s start %d goal %d moves %d vertex %d edge %d follows %d",
                name,
                validation$verdict,
                validation$start,
                validation$goal,
                validation$moves,
                validation$vertex,
                validation$edge,
                validation$follows
            )
        )
        for (conflict in validation$conflicts) {
            text <- paste0("  ", conflict_text(conflict, grid))
            if (name == "INDEPENDENT") text <- paste(text, conflict$classification)
            lines <- c(lines, text)
        }
    }
    lines
}

trace_lines <- function(runs) {
    lines <- character()
    for (index in seq_along(runs)) {
        if (index > 1L) lines <- c(lines, "")
        run <- runs[[index]]
        lines <- c(lines, paste("run", run$name), run$trace, run$ending)
    }
    lines
}

animation_lines <- function(runs, grid, agents, settings) {
    selected <- Filter(function(run) run$name == settings$animate, runs)[[1L]]
    if (selected$status != "OK") return(paste("run", selected$name, "FAIL"))
    paths <- selected$paths
    lines <- sprintf("run %s frames %d", selected$name, settings$frames)
    for (time in seq_len(settings$frames) - 1L) {
        done <- sum(lengths(paths) - 1L <= time)
        moving <- sum(vapply(
            paths,
            function(path) time < length(path) - 1L && time >= 1L && path_position(
                path,
                time
            ) != path_position(
                path,
                time - 1L
            ),
            FALSE
        ))
        waiting <- length(paths) - done - moving
        lines <- c(lines, "", sprintf("frame %d done %d moving %d waiting %d", time, done, moving, waiting))
        placements <- new.env(parent = emptyenv())
        for (agent in agents) placements[[as.character(agent$goal)]] <- tolower(agent$name)
        for (index in seq_along(agents)) placements[[as.character(path_position(
            paths[[index]],
            time
        ))]] <- agents[[index]]$name
        lines <- c(lines, grid_picture(grid, placements))
    }
    for (name in c("traffic", "waits")) {
        counts <- if (name == "traffic") selected$metrics$traffic else selected$metrics$cell_waits
        placements <- new.env(parent = emptyenv())
        for (key in ls(counts)) {
            value <- counts[[key]]
            if (value > 0L) placements[[key]] <- if (value <= 9L) as.character(value) else "+"
        }
        lines <- c(lines, "", name, grid_picture(grid, placements))
    }
    lines
}

main <- function() {
    grid <- read_grid()
    agents <- read_agents(grid)
    settings <- read_parameters(length(agents))
    distances <- lapply(agents, function(agent) distance_table(grid, agent$goal))
    independent <- independent_plan(grid, agents, distances, settings$horizon)
    overview <- instance_overview(grid, agents, distances, independent)
    runs <- list()
    for (definition in settings$runs) {
        run <- new_run(definition, settings)
        if (run$solver == "PP") {
            solve_pp(run, grid, agents, distances, settings)
        } else if (run$solver %in% c("CBS", "ICBS")) {
            solve_cbs(run, grid, agents, distances, settings)
        } else {
            solve_whca(run, grid, agents, distances, settings)
        }
        if (run$status == "OK") {
            run$metrics <- plan_statistics(run$paths, agents, overview, run$cost_function, grid)
            run$validation <- validate_plan(run$paths, agents, grid)
            run$execution <- delayed_execution(run$paths, settings)
        }
        runs[[length(runs) + 1L]] <- run
    }
    save_file("solutions.txt", solution_lines(grid, agents, overview, runs))
    save_file("stats.csv", stats_lines(runs))
    save_file("validation.txt", validation_lines(runs, independent, agents, grid, overview))
    save_file("trace.txt", trace_lines(runs))
    save_file("frames.txt", animation_lines(runs, grid, agents, settings))
}

main()
