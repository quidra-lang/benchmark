options(scipen = 999)
emit <- function(...) cat(paste0(...), "\n", sep = "")
fail <- function(text) stop(text, call. = FALSE)
take <- function(x, n) head(x, n)
drop <- function(x, n) if (n == 0) x else x[-seq_len(n)]
segment <- function(x, i, j) take(drop(x, i), j - i)
lex_less <- function(a, b) {
    if (is.null(b)) return(TRUE)
    different <- which(a != b)
    length(different) > 0 && a[different[1]] < b[different[1]]
}

make_workbench <- function() {
    state <- new.env(parent = emptyenv())
    state$depot <- NULL
    state$departure <- 480
    state$stops <- list()
    state$tour <- NULL
    state$routes <- NULL
    state$capacity <- NULL
    ids <- function() sort(as.integer(names(state$stops)))
    stop_at <- function(id) state$stops[[as.character(id)]]
    location_name <- function(id) if (id == 0) "D" else as.character(id)
    point <- function(id) {
        if (id == 0) return(state$depot)
        s <- stop_at(id)
        c(s$x, s$y)
    }
    distance <- function(a, b) sum(abs(point(a) - point(b)))
    route_length <- function(route) {
        result <- 0
        previous <- 0
        for (id in route) {
            result <- result + distance(previous, id)
            previous <- id
        }
        result + distance(previous, 0)
    }
    load <- function(route) sum(vapply(route, function(id) stop_at(id)$demand, numeric(1)))
    notation <- function(route) paste(c("D", route, "D"), collapse = "-")
    plan_length <- function(routes = state$routes) sum(vapply(routes, route_length, numeric(1)))
    normalize <- function() {
        routes <- Filter(function(route) length(route) > 0, state$routes)
        routes <- lapply(routes, function(route) if (route[1] > tail(route, 1)) rev(route) else route)
        state$routes <- routes[order(vapply(routes, min, numeric(1)))]
    }
    route_lines <- function() {
        for (i in seq_along(state$routes)) {
            route <- state$routes[[i]]
            emit("route ", i, ": ", notation(route), " load ", load(route), " length ", route_length(route))
        }
    }
    clock <- function(time) sprintf("%02d:%02d", as.integer(time %/% 60), as.integer(time %% 60))
    minutes <- function(text) {
        parts <- as.integer(strsplit(text, ":", fixed = TRUE)[[1]])
        parts[1] * 60 + parts[2]
    }
    require_data <- function() {
        if (is.null(state$depot)) fail("no depot")
        if (length(state$stops) == 0) fail("no stops")
    }
    require_tour <- function() if (is.null(state$tour)) fail("no tour")
    require_plan <- function() if (is.null(state$routes)) fail("no plan")
    check_capacity <- function(capacity) {
        for (id in ids()) {
            if (stop_at(id)$demand > capacity) {
                fail(paste0("stop ", id, " demand ", stop_at(id)$demand, " exceeds capacity ", capacity))
            }
        }
    }
    simulate <- function(route, output = FALSE) {
        time <- state$departure
        previous <- 0
        waiting <- service <- violations <- lateness <- 0
        for (id in route) {
            s <- stop_at(id)
            arrival <- time + distance(previous, id)
            wait <- if (is.null(s$open)) 0 else max(0, s$open - arrival)
            late <- if (is.null(s$close)) 0 else max(0, arrival - s$close)
            begin <- arrival + wait
            time <- begin + s$service
            waiting <- waiting + wait
            service <- service + s$service
            violations <- violations + as.integer(late > 0)
            lateness <- lateness + late
            if (output) {
                emit(id, " arrive ", clock(arrival), " wait ", wait, " begin ", clock(begin), " leave ", clock(time), " ", if (late > 0) paste0("late ", late) else "ok")
            }
            previous <- id
        }
        time <- time + distance(previous, 0)
        if (output) {
            emit("return ", clock(time), ", travel ", route_length(route), ", wait ", waiting, ", service ", service, ", violations ", violations, ", lateness ", lateness)
        }
        c(time, violations, lateness)
    }
    exact <- function() {
        stops <- ids()
        full <- bitwShiftL(1L, length(stops)) - 1L
        memo <- new.env(hash = TRUE, parent = emptyenv())
        solve <- function(mask, previous) {
            if (mask == full) return(distance(previous, 0))
            key <- paste(mask, previous, sep = ",")
            cached <- get0(key, envir = memo, inherits = FALSE)
            if (!is.null(cached)) return(cached)
            best <- Inf
            for (i in seq_along(stops)) {
                bit <- bitwShiftL(1L, i - 1L)
                if (bitwAnd(mask, bit) == 0L) {
                    best <- min(best, distance(previous, stops[i]) + solve(bitwOr(mask, bit), stops[i]))
                }
            }
            assign(key, best, envir = memo)
            best
        }
        route <- integer()
        mask <- previous <- 0L
        while (mask != full) {
            best <- solve(mask, previous)
            for (i in seq_along(stops)) {
                bit <- bitwShiftL(1L, i - 1L)
                if (bitwAnd(mask, bit) == 0L && distance(previous, stops[i]) + solve(bitwOr(mask, bit), stops[i]) == best) {
                    route <- c(route, stops[i])
                    mask <- bitwOr(mask, bit)
                    previous <- stops[i]
                    break
                }
            }
        }
        route
    }
    tour_move <- function(route, method) {
        old <- route_length(route)
        n <- length(route)
        if (method == "OROPT") {
            for (size in 1:3) {
                if (size > n) next
                for (i in 0:(n - size)) {
                    part <- segment(route, i, i + size)
                    remaining <- c(take(route, i), drop(route, i + size))
                    for (j in 0:length(remaining)) {
                        if (j == i) next
                        candidate <- append(remaining, part, after = j)
                        gain <- old - route_length(candidate)
                        if (gain > 0) {
                            after <- if (j == 0) "D" else remaining[j]
                            return(list(route = candidate, message = paste0("move ", paste(part, collapse = "-"), " after ", after, " gain ", gain)))
                        }
                    }
                }
            }
        } else if (n >= 2) {
            for (i in seq_len(n - 1L)) {
                for (j in seq.int(i + 1L, n)) {
                    candidate <- route
                    if (method == "TWOOPT") {
                        candidate[i:j] <- rev(candidate[i:j])
                    } else {
                        candidate[c(i, j)] <- candidate[c(j, i)]
                    }
                    gain <- old - route_length(candidate)
                    if (gain > 0) {
                        message <- if (method == "TWOOPT") paste0("reverse ", route[i], "..", route[j], " gain ", gain) else paste0("swap ", route[i], " and ", route[j], " gain ", gain)
                        return(list(route = candidate, message = message))
                    }
                }
            }
        }
        NULL
    }
    improve_tour <- function(route, method, output = TRUE) {
        count <- 0
        repeat {
            move <- tour_move(route, method)
            if (is.null(move)) break
            route <- move$route
            if (output) emit(move$message)
            count <- count + 1
        }
        list(route = route, count = count)
    }
    plan_move <- function(method) {
        before <- plan_length()
        k <- length(state$routes)
        for (r in seq_len(k)) {
            a <- state$routes[[r]]
            if (method == "RELOCATE") {
                for (p in seq_along(a)) {
                    c <- a[p]
                    for (t in seq_len(k)) {
                        b <- state$routes[[t]]
                        if (r == t || load(b) + stop_at(c)$demand > state$capacity) next
                        for (j in 0:length(b)) {
                            candidate <- state$routes
                            candidate[[r]] <- a[-p]
                            candidate[[t]] <- append(b, c, after = j)
                            gain <- before - plan_length(candidate)
                            if (gain > 0) {
                                after <- if (j == 0) "D" else b[j]
                                return(list(routes = candidate, message = paste0("relocate ", c, " from route ", r, " to route ", t, " after ", after, " gain ", gain)))
                            }
                        }
                    }
                }
            } else if (r < k) {
                for (t in seq.int(r + 1L, k)) {
                    b <- state$routes[[t]]
                    if (method == "EXCHANGE") {
                        for (p in seq_along(a)) {
                            c <- a[p]
                            for (j in seq_along(b)) {
                                e <- b[j]
                                if (load(a) - stop_at(c)$demand + stop_at(e)$demand > state$capacity || load(b) - stop_at(e)$demand + stop_at(c)$demand > state$capacity) next
                                candidate <- state$routes
                                candidate[[r]][p] <- e
                                candidate[[t]][j] <- c
                                gain <- before - plan_length(candidate)
                                if (gain > 0) return(list(routes = candidate, message = paste0("exchange ", c, " (route ", r, ") with ", e, " (route ", t, ") gain ", gain)))
                            }
                        }
                    } else {
                        for (i in 0:length(a)) {
                            for (j in 0:length(b)) {
                                left <- c(take(a, i), drop(b, j))
                                right <- c(take(b, j), drop(a, i))
                                if (load(left) > state$capacity || load(right) > state$capacity) next
                                candidate <- state$routes
                                candidate[[r]] <- left
                                candidate[[t]] <- right
                                gain <- before - plan_length(candidate)
                                if (gain > 0) {
                                    x <- if (i == 0) "D" else a[i]
                                    y <- if (j == 0) "D" else b[j]
                                    return(list(routes = candidate, message = paste0("cross route ", r, " after ", x, " with route ", t, " after ", y, " gain ", gain)))
                                }
                            }
                        }
                    }
                }
            }
        }
        NULL
    }
    bounds <- function() {
        tree <- 0
        remaining <- ids()
        edges <- character()
        mst <- 0
        while (length(remaining) > 0) {
            best <- NULL
            for (id in remaining) {
                for (i in seq_along(tree)) {
                    choice <- c(distance(tree[i], id), id, i)
                    if (lex_less(choice, best)) best <- choice
                }
            }
            weight <- best[1]
            c <- best[2]
            edges <- c(edges, paste0(location_name(tree[best[3]]), "-", c))
            mst <- mst + weight
            tree <- c(tree, c)
            remaining <- remaining[remaining != c]
        }
        emit("mst: ", paste(edges, collapse = " "), " (length ", mst, ")")
        stops <- ids()
        if (length(stops) == 1) {
            one_tree <- 2 * distance(0, stops[1])
        } else {
            tree <- stops[1]
            remaining <- stops[-1]
            cost <- 0
            while (length(remaining) > 0) {
                best <- NULL
                for (id in remaining) {
                    for (parent in tree) {
                        choice <- c(distance(parent, id), id)
                        if (lex_less(choice, best)) best <- choice
                    }
                }
                cost <- cost + best[1]
                tree <- c(tree, best[2])
                remaining <- remaining[remaining != best[2]]
            }
            one_tree <- cost + sum(head(sort(vapply(stops, function(id) distance(0, id), numeric(1))), 2))
        }
        best <- max(mst, one_tree)
        emit("bound: mst ", mst, ", one-tree ", one_tree, ", best ", best)
        if (is.null(state$tour)) {
            emit("gap: no tour")
        } else {
            value <- route_length(state$tour)
            u <- if (best > 0) (2000 * (value - best) + best) %/% (2 * best) else 0
            emit("gap: tour ", value, ", ", u %/% 10, ".", u %% 10, "%")
        }
    }
    create_plan <- function(command, args) {
        capacity <- as.integer(args[1])
        if (command == "SPLIT") require_tour() else require_data()
        check_capacity(capacity)
        limit <- if (command == "VRP" && length(args) > 1) as.integer(args[2]) else NULL
        if (!is.null(limit)) {
            for (id in ids()) {
                if (2 * distance(0, id) > limit) fail(paste0("stop ", id, " too far for limit ", limit))
            }
        }
        merges <- 0
        if (command == "VRP") {
            stops <- ids()
            routes <- lapply(stops, function(id) id)
            savings <- list()
            if (length(stops) >= 2) {
                for (p in seq_len(length(stops) - 1L)) {
                    for (q in seq.int(p + 1L, length(stops))) {
                        i <- stops[p]
                        j <- stops[q]
                        saving <- distance(0, i) + distance(0, j) - distance(i, j)
                        if (saving > 0) savings[[length(savings) + 1L]] <- c(-saving, i, j)
                    }
                }
            }
            if (length(savings) > 0) {
                keys <- do.call(rbind, savings)
                savings <- savings[order(keys[, 1], keys[, 2], keys[, 3])]
            }
            for (pair in savings) {
                i <- pair[2]
                j <- pair[3]
                r <- which(vapply(routes, function(route) i %in% route, logical(1)))[1]
                t <- which(vapply(routes, function(route) j %in% route, logical(1)))[1]
                a <- routes[[r]]
                b <- routes[[t]]
                if (r == t || !(i %in% c(a[1], tail(a, 1))) || !(j %in% c(b[1], tail(b, 1))) || load(a) + load(b) > capacity) next
                joined <- c(if (a[1] == i) rev(a) else a, if (tail(b, 1) == j) rev(b) else b)
                if (!is.null(limit) && route_length(joined) > limit) next
                routes[[r]] <- joined
                routes <- routes[-t]
                merges <- merges + 1
            }
        } else if (command == "SPLIT") {
            values <- c(0, rep(0, length(state$tour)))
            parents <- integer(length(state$tour))
            for (j in seq_along(state$tour)) {
                best <- NULL
                for (i in 0:(j - 1L)) {
                    part <- segment(state$tour, i, j)
                    if (load(part) <= capacity) {
                        choice <- c(values[i + 1L] + route_length(part), i)
                        if (lex_less(choice, best)) best <- choice
                    }
                }
                values[j + 1L] <- best[1]
                parents[j] <- best[2]
            }
            routes <- list()
            j <- length(state$tour)
            while (j > 0) {
                routes[[length(routes) + 1L]] <- segment(state$tour, parents[j], j)
                j <- parents[j]
            }
        } else {
            angle_less <- function(a, b) {
                av <- point(a) - state$depot
                bv <- point(b) - state$depot
                az <- all(av == 0)
                bz <- all(bv == 0)
                if (az || bz) return(if (az == bz) a < b else az)
                ah <- if (av[2] > 0 || (av[2] == 0 && av[1] > 0)) 0 else 1
                bh <- if (bv[2] > 0 || (bv[2] == 0 && bv[1] > 0)) 0 else 1
                if (ah != bh) return(ah < bh)
                cross <- av[1] * bv[2] - av[2] * bv[1]
                if (cross != 0) return(cross > 0)
                lex_less(c(distance(0, a), a), c(distance(0, b), b))
            }
            sweep <- integer()
            for (id in ids()) {
                j <- 0
                while (j < length(sweep) && !angle_less(id, sweep[j + 1L])) j <- j + 1L
                sweep <- append(sweep, id, after = j)
            }
            routes <- list(integer())
            for (id in sweep) {
                last <- length(routes)
                if (load(routes[[last]]) + stop_at(id)$demand > capacity) {
                    routes[[last + 1L]] <- integer()
                    last <- last + 1L
                }
                routes[[last]] <- c(routes[[last]], id)
            }
        }
        state$capacity <- capacity
        state$routes <- routes
        normalize()
        extra <- if (command == "VRP") paste0(" merges ", merges, ",") else ""
        emit(tolower(command), ": capacity ", capacity, ",", extra, " routes ", length(state$routes), ", length ", plan_length())
        route_lines()
    }
    execute <- function(line) {
        words <- strsplit(line, " ", fixed = TRUE)[[1]]
        command <- words[1]
        args <- words[-1]
        if (command == "DEPOT") {
            state$depot <- as.integer(args)
            emit("depot at (", paste(state$depot, collapse = ","), ")")
        } else if (command == "START") {
            state$departure <- minutes(args[1])
            emit("start ", clock(state$departure))
        } else if (command == "STOP") {
            numbers <- as.integer(args[1:5])
            id <- numbers[1]
            if (!is.null(stop_at(id))) fail(paste0("stop ", id, " already exists"))
            opening <- if (length(args) > 5) minutes(args[6]) else NULL
            closing <- if (length(args) > 5) minutes(args[7]) else NULL
            if (!is.null(opening) && opening > closing) fail("invalid window")
            state$stops[[as.character(id)]] <- list(x = numbers[2], y = numbers[3], demand = numbers[4], service = numbers[5], open = opening, close = closing)
            state$tour <- state$routes <- NULL
            emit("stop ", id, " added")
        } else if (command == "REMOVE") {
            id <- as.integer(args[1])
            if (is.null(stop_at(id))) fail(paste0("unknown stop ", id))
            state$stops[[as.character(id)]] <- NULL
            if (length(state$stops) == 0) {
                state$tour <- state$routes <- NULL
            } else {
                if (!is.null(state$tour)) state$tour <- state$tour[state$tour != id]
                if (!is.null(state$routes)) {
                    state$routes <- lapply(state$routes, function(route) route[route != id])
                    normalize()
                }
            }
            emit("stop ", id, " removed")
        } else if (command == "LIST") {
            emit(if (is.null(state$depot)) "depot none" else paste0("depot (", paste(state$depot, collapse = ","), ")"))
            emit("start ", clock(state$departure))
            emit("stops ", length(state$stops))
            for (id in ids()) {
                s <- stop_at(id)
                window <- if (is.null(s$open)) "none" else paste0(clock(s$open), "-", clock(s$close))
                emit(id, " at (", s$x, ",", s$y, ") demand ", s$demand, " service ", s$service, " window ", window)
            }
        } else if (command == "MATRIX") {
            if (is.null(state$depot)) fail("no depot")
            locations <- c(0, ids())
            cells <- list(c("", vapply(locations, location_name, character(1))))
            for (a in locations) cells[[length(cells) + 1L]] <- c(location_name(a), as.character(vapply(locations, function(b) distance(a, b), numeric(1))))
            width <- max(nchar(unlist(cells), type = "bytes"))
            for (row in cells) emit(paste(sprintf(paste0("%", width, "s"), row), collapse = " "))
        } else if (command %in% c("ORDER", "NEAREST", "INSERTION", "EXACT")) {
            require_data()
            if (command == "ORDER") {
                route <- as.integer(args)
                for (id in route) if (is.null(stop_at(id))) fail(paste0("unknown stop ", id))
                seen <- integer()
                for (id in route) {
                    if (id %in% seen) fail(paste0("duplicate stop ", id))
                    seen <- c(seen, id)
                }
                if (length(route) != length(state$stops)) fail(paste0("order has ", length(route), " stops, expected ", length(state$stops)))
            } else if (command == "EXACT") {
                if (length(state$stops) > 10) fail(paste0("too many stops for exact (", length(state$stops), ")"))
                route <- exact()
            } else {
                route <- integer()
                while (length(route) < length(state$stops)) {
                    remaining <- setdiff(ids(), route)
                    best <- NULL
                    for (c in remaining) {
                        if (command == "NEAREST") {
                            previous <- if (length(route) == 0) 0 else tail(route, 1)
                            choice <- c(distance(previous, c), c)
                            if (lex_less(choice, best)) best <- choice
                        } else {
                            for (j in 0:length(route)) {
                                candidate <- append(route, c, after = j)
                                choice <- c(route_length(candidate) - route_length(route), c, j)
                                if (lex_less(choice, best)) best <- choice
                            }
                        }
                    }
                    route <- if (command == "NEAREST") c(route, best[2]) else append(route, best[2], after = best[3])
                }
            }
            state$tour <- route
            emit(tolower(command), ": ", notation(route), " length ", route_length(route))
        } else if (command == "TOUR") {
            require_tour()
            emit("tour: ", notation(state$tour), " length ", route_length(state$tour))
        } else if (command %in% c("TWOOPT", "OROPT", "SWAP")) {
            require_tour()
            before <- route_length(state$tour)
            result <- improve_tour(state$tour, command)
            state$tour <- result$route
            emit(tolower(command), ": moves ", result$count, ", length ", before, " -> ", route_length(state$tour))
        } else if (command == "TIMECHECK") {
            if (length(args) == 0) {
                require_tour()
                emit("timecheck tour depart ", clock(state$departure))
                simulate(state$tour, TRUE)
            } else {
                require_plan()
                r <- as.integer(args[1])
                if (r > length(state$routes)) fail(paste0("no route ", r))
                emit("timecheck route ", r, " depart ", clock(state$departure))
                simulate(state$routes[[r]], TRUE)
            }
        } else if (command == "BOUND") {
            require_data()
            bounds()
        } else if (command %in% c("VRP", "SPLIT", "SWEEP")) {
            create_plan(command, args)
        } else if (command == "ROUTES") {
            require_plan()
            emit("plan: capacity ", state$capacity, ", routes ", length(state$routes), ", length ", plan_length())
            route_lines()
        } else if (command %in% c("RELOCATE", "EXCHANGE", "CROSS")) {
            require_plan()
            before <- plan_length()
            old_count <- length(state$routes)
            count <- 0
            repeat {
                move <- plan_move(command)
                if (is.null(move)) break
                state$routes <- move$routes
                emit(move$message)
                normalize()
                count <- count + 1
            }
            extra <- if (command == "EXCHANGE") "" else paste0(" routes ", old_count, " -> ", length(state$routes), ",")
            emit(tolower(command), ": moves ", count, ",", extra, " length ", before, " -> ", plan_length())
        } else if (command == "ROUTEOPT") {
            require_plan()
            before <- plan_length()
            for (r in seq_along(state$routes)) {
                old <- route_length(state$routes[[r]])
                result <- improve_tour(state$routes[[r]], "TWOOPT", FALSE)
                state$routes[[r]] <- result$route
                emit("route ", r, ": moves ", result$count, ", length ", old, " -> ", route_length(result$route))
            }
            normalize()
            emit("routeopt: length ", before, " -> ", plan_length())
        } else if (command == "REPORT") {
            emit("report: stops ", length(state$stops), ", demand ", sum(vapply(state$stops, function(s) s$demand, numeric(1))), ", service ", sum(vapply(state$stops, function(s) s$service, numeric(1))), ", windows ", sum(vapply(state$stops, function(s) !is.null(s$open), logical(1))))
            if (is.null(state$tour)) {
                emit("tour: none")
            } else {
                run <- simulate(state$tour)
                emit("tour: length ", route_length(state$tour), ", return ", clock(run[1]), ", violations ", run[2], ", lateness ", run[3])
            }
            if (is.null(state$routes)) {
                emit("plan: none")
            } else {
                runs <- do.call(rbind, lapply(state$routes, simulate))
                denominator <- length(state$routes) * state$capacity
                weight <- sum(vapply(state$routes, load, numeric(1)))
                u <- (2000 * weight + denominator) %/% (2 * denominator)
                emit("plan: capacity ", state$capacity, ", routes ", length(state$routes), ", length ", plan_length(), ", utilization ", u %/% 10, ".", u %% 10, "%, return ", clock(max(runs[, 1])), ", violations ", sum(runs[, 2]), ", lateness ", sum(runs[, 3]))
            }
        }
        invisible(NULL)
    }
    function(line) tryCatch(execute(line), error = function(error) emit("error: ", conditionMessage(error)))
}

input <- readLines(file("stdin"), warn = FALSE)
workbench <- make_workbench()
count <- as.integer(input[1])
for (i in seq_len(count)) workbench(input[i + 1L])
