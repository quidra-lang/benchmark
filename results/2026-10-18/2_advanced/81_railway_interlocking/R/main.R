source("layout.R")
source("interlocking.R")
source("signals.R")
source("trains.R")
source("safety.R")

read_simulation <- function() {
    simulation <- new.env(parent = emptyenv())
    simulation$layout <- read_layout()
    simulation$routes <- read_routes(simulation$layout)
    plans <- read_trains()
    simulation$trains <- plans$trains
    simulation$planned <- new.env(parent = emptyenv())
    for (request in plans$requests) {
        key <- as.character(request$time)
        simulation$planned[[key]] <- c(simulation$planned[[key]], list(request))
    }
    simulation$events <- new.env(parent = emptyenv())
    for (line in readLines("input/events.txt", warn = FALSE)) {
        fields <- strsplit(line, " ", fixed = TRUE)[[1L]]
        key <- fields[1L]
        event <- list(command = fields[2L], arguments = fields[-c(1L, 2L)])
        simulation$events[[key]] <- c(simulation$events[[key]], list(event))
    }
    settings <- list()
    for (line in readLines("input/params.txt", warn = FALSE)) {
        fields <- strsplit(line, " ", fixed = TRUE)[[1L]]
        settings[[fields[1L]]] <- as.integer(fields[-1L])
    }
    simulation$end_time <- settings$END
    simulation$throw_time <- settings$THROW
    simulation$overlap_time <- settings$OVERLAP
    simulation$snapshot_times <- settings$SNAPSHOTS
    simulation$time <- simulation$request_count <- simulation$dropped <- 0L
    simulation$queue <- list()
    simulation$log_lines <- simulation$snapshots <- character()
    simulation$safety <- new_safety()
    simulation
}

log_event <- function(simulation, content) simulation$log_lines <- c(
    simulation$log_lines,
    paste(simulation$time, content)
)
track_occupied <- function(
    simulation,
    name
) simulation$layout$sections[[name]]$failed || length(simulation$layout$sections[[name]]$occupants) > 0L

start_throw <- function(simulation, point, target) {
    point$moving <- TRUE
    point$target <- target
    point$completion <- simulation$time + simulation$throw_time
    log_event(simulation, sprintf("MOVE %s %s until %d", point$name, target, point$completion))
}

complete_throws <- function(simulation) {
    for (point in simulation$layout$points) {
        if (point$moving && point$completion == simulation$time) {
            point$position <- point$target
            point$moving <- FALSE
            point$completion <- -1L
            point$throws <- point$throws + 1L
            log_event(simulation, paste("POINT", point$name, point$position))
        }
    }
}

release_approaches <- function(simulation) {
    for (route in simulation$routes) {
        if (route$state == "APPROACH" && route$release_time == simulation$time) {
            release_route(simulation$layout, route)
            log_event(simulation, paste("TIMEOUT", route$name))
        }
    }
}

add_request <- function(simulation, name, requester) {
    simulation$request_count <- simulation$request_count + 1L
    request <- new.env(parent = emptyenv())
    request$number <- simulation$request_count
    request$route <- name
    request$time <- simulation$time
    request$reason <- ""
    simulation$queue[[length(simulation$queue) + 1L]] <- request
    simulation$routes[[name]]$requests <- simulation$routes[[name]]$requests + 1L
    log_event(simulation, sprintf("REQUEST q%d %s %s", request$number, name, requester))
}

cancel_route <- function(simulation, name) {
    removed <- Filter(function(request) request$route == name, simulation$queue)
    if (length(removed)) {
        for (request in removed) {
            log_event(simulation, sprintf("DROP q%d %s", request$number, name))
            simulation$dropped <- simulation$dropped + 1L
        }
        simulation$queue <- Filter(function(request) request$route != name, simulation$queue)
        return(invisible(NULL))
    }
    route <- simulation$routes[[name]]
    if (route$state == "LOCKED") {
        route$cancels <- route$cancels + 1L
        signal <- simulation$layout$signals[[route$start]]
        if (signal$aspect != "RED" && track_occupied(simulation, signal$section)) {
            route$state <- "APPROACH"
            route$release_time <- simulation$time + route$approach_time
            log_event(simulation, sprintf("CANCEL %s approach until %d", name, route$release_time))
        } else {
            release_route(simulation$layout, route)
            log_event(simulation, paste("CANCEL", name, "released"))
        }
    } else {
        log_event(simulation, paste("CANCEL", name, if (nzchar(route$state)) "refused" else "none"))
    }
}

individual_throw <- function(simulation, name, target) {
    point <- simulation$layout$points[[name]]
    result <- if (length(point$locks)) "locked" else if (point$failed) "failed" else if (point$moving) "moving" else if (track_occupied(
        simulation,
        point$common
    )) "occupied" else if (point$position == target) "none" else "start"
    log_event(simulation, paste("THROW", name, target, result))
    if (result == "start") start_throw(simulation, point, target)
}

execute_events <- function(simulation) {
    for (event in simulation$events[[as.character(simulation$time)]]) {
        command <- event$command
        arguments <- event$arguments
        name <- arguments[1L]
        if (command == "REQUEST") {
            add_request(simulation, name, "OPERATOR")
        } else if (command == "CANCEL") {
            cancel_route(simulation, name)
        } else if (command == "THROW") {
            individual_throw(simulation, name, arguments[2L])
        } else if (command %in% c("TCFAIL", "TCFIX")) {
            simulation$layout$sections[[name]]$failed <- command == "TCFAIL"
            log_event(simulation, paste(command, name))
        } else {
            point <- simulation$layout$points[[name]]
            point$failed <- command == "POINTFAIL"
            if (point$failed && point$moving) point$completion <- -1L
            log_event(simulation, paste(command, name))
            if (!point$failed && point$moving) start_throw(simulation, point, point$target)
        }
    }
}

opposite_lock <- function(simulation, names, route) any(vapply(
    names,
    function(name) simulation$routes[[name]]$direction != route$direction,
    FALSE
))

request_reason <- function(simulation, route) {
    if (nzchar(route$state)) return("busy")
    for (name in route$conflicts) if (simulation$routes[[name]]$state %in% c(
        "LOCKED",
        "APPROACH"
    )) return(paste("conflict", name))
    for (name in route$sections) {
        section <- simulation$layout$sections[[name]]
        if (track_occupied(simulation, name)) return(paste("occupied", name))
        if (nzchar(section$route_lock) || opposite_lock(
            simulation,
            section$overlap_locks,
            route
        )) return(paste("locked", name))
    }
    for (name in route$overlap) {
        section <- simulation$layout$sections[[name]]
        if (track_occupied(simulation, name)) return(paste("occupied", name))
        locks <- section$overlap_locks
        if (nzchar(section$route_lock)) locks <- union(locks, section$route_lock)
        if (opposite_lock(simulation, locks, route)) return(paste("locked", name))
    }
    for (entry in route$requirements) {
        name <- entry$name
        target <- entry$position
        point <- simulation$layout$points[[name]]
        if (any(vapply(
            point$locks,
            function(lock) lock$position != target,
            FALSE
        ))) return(paste("point", name, "locked"))
        if ((!point$moving && point$position == target) || (point$moving && point$target == target)) next
        if (point$failed) return(paste("point", name, "failed"))
        if (point$moving) return(paste("point", name, "moving"))
        if (track_occupied(simulation, point$common)) return(paste("point", name, "occupied"))
    }
    NULL
}

judge_requests <- function(simulation) {
    waiting <- list()
    for (request in simulation$queue) {
        route <- simulation$routes[[request$route]]
        reason <- request_reason(simulation, route)
        if (!is.null(reason)) {
            if (reason != request$reason) {
                log_event(simulation, sprintf("WAIT q%d %s %s", request$number, route$name, reason))
                request$reason <- reason
            }
            waiting[[length(waiting) + 1L]] <- request
            next
        }
        lock_route(simulation$layout, route)
        wait <- simulation$time - request$time
        route$grants <- route$grants + 1L
        route$wait <- route$wait + wait
        route$maxwait <- max(route$maxwait, wait)
        log_event(simulation, sprintf("GRANT q%d %s wait %d", request$number, route$name, wait))
        for (entry in route$requirements) {
            point <- simulation$layout$points[[entry$name]]
            if (!point$moving && point$position != entry$position) start_throw(
                simulation,
                point,
                entry$position
            )
        }
    }
    simulation$queue <- waiting
}

decide_signals <- function(simulation) {
    decisions <- signal_aspects(
        simulation$layout,
        simulation$routes,
        function(name) track_occupied(simulation, name)
    )
    for (entry in decisions) {
        signal <- entry$signal
        if (signal$aspect != entry$aspect) {
            signal$aspect <- entry$aspect
            log_event(simulation, paste("SIGNAL", signal$name, entry$aspect))
        }
    }
}

occupied_parts <- function(simulation, train) {
    parts <- list()
    if (train$state == "RUNNING") {
        tail <- train$head - train$length
        for (entry in train$path) {
            stop <- entry$start + simulation$layout$sections[[entry$name]]$length
            if (entry$start < train$head && stop > tail) parts[[length(parts) + 1L]] <- list(
                name = entry$name,
                start = entry$start,
                low = max(tail, entry$start),
                high = min(train$head, stop)
            )
        }
    }
    parts
}

head_section <- function(train) {
    for (entry in rev(train$path)) if (entry$start < train$head) return(entry)
    train$path[[1L]]
}

enter_train <- function(simulation, train, entered_boundaries) {
    if (train$state == "EXITED") return(FALSE)
    if (train$state == "RUNNING") return(TRUE)
    boundary <- simulation$layout$boundaries[[train$entry]]
    if (simulation$time < train$entry_time || track_occupied(simulation, boundary$section) || exists(
        train$entry,
        entered_boundaries,
        inherits = FALSE
    )) return(FALSE)
    train$state <- "RUNNING"
    train$direction <- if (boundary$endpoint == "L") "UP" else "DOWN"
    train$path <- list(list(name = boundary$section, start = 0L))
    train$head <- 0L
    train$speed <- train$entry_speed
    train$entered <- simulation$time
    entered_boundaries[[train$entry]] <- TRUE
    log_event(simulation, paste("ENTER", train$name, train$entry))
    TRUE
}

reverse_train <- function(simulation, train, stop) {
    head <- head_section(train)
    endpoint <- head$start + simulation$layout$sections[[head$name]]$length
    parts <- occupied_parts(simulation, train)
    train$path <- lapply(
        rev(parts),
        function(entry) list(
            name = entry$name,
            start = endpoint - (entry$start + simulation$layout$sections[[entry$name]]$length)
        )
    )
    train$head <- endpoint - (train$head - train$length)
    train$direction <- if (train$direction == "UP") "DOWN" else "UP"
    log_event(simulation, paste("REVERSE", train$name, stop$section))
}

finish_dwell <- function(simulation, train) {
    if (!train$dwelling) return(TRUE)
    stop <- next_stop(train)
    if (simulation$time < stop$arrival + stop$dwell || simulation$time < stop$scheduled_departure) return(FALSE)
    train$dwelling <- FALSE
    train$awaiting_departure <- stop
    train$stop_index <- train$stop_index + 1L
    if (stop$kind == "TURN") reverse_train(simulation, train, stop)
    TRUE
}

limit_distance <- function(simulation, train) {
    if (nzchar(train$boundary)) return(NULL)
    head <- head_section(train)
    name <- head$name
    distance <- head$start + simulation$layout$sections[[name]]$length - train$head
    stop <- next_stop(train)
    repeat {
        signal <- simulation$layout$signals_at[[paste(name, train$direction)]]
        if (!is.null(signal) && signal$aspect == "RED") return(distance)
        if (!is.null(stop) && stop$section == name) return(distance)
        following <- beyond(simulation$layout, name, train$direction)
        if (following$kind == "boundary") return(NULL)
        if (following$kind %in% c("buffer", "impassable")) return(distance)
        distance <- distance + simulation$layout$sections[[following$name]]$length
        name <- following$name
    }
}

pass_signal <- function(simulation, train, signal) {
    eligible <- Filter(
        function(route) route$start == signal$name && route$state %in% c("LOCKED", "APPROACH"),
        simulation$routes
    )
    route <- if (length(eligible)) eligible[[1L]] else NULL
    log_event(
        simulation,
        paste("PASS", train$name, signal$name, signal$aspect, if (is.null(route)) "-" else route$name)
    )
    signal$passes <- signal$passes + 1L
    train$passes <- train$passes + 1L
    if (!is.null(route)) {
        route$state <- "USED"
        route$uses <- route$uses + 1L
    }
    if (signal$aspect == "RED") {
        log_event(simulation, paste("SPAD", train$name, signal$name))
        safety_check(simulation$safety, simulation$time, "SIGNAL_PASSING", paste(train$name, signal$name))
        train$emergency <- TRUE
    } else {
        safety_check(simulation$safety, simulation$time, "SIGNAL_PASSING")
    }
}

move_train <- function(simulation, train, distance) {
    head <- head_section(train)
    name <- head$name
    start <- head$start
    remaining <- distance
    while (remaining > 0L) {
        if (nzchar(train$boundary)) {
            train$head <- train$head + remaining
            break
        }
        endpoint <- start + simulation$layout$sections[[name]]$length
        if (train$head + remaining <= endpoint) {
            train$head <- train$head + remaining
            break
        }
        remaining <- remaining - (endpoint - train$head)
        train$head <- endpoint
        signal <- simulation$layout$signals_at[[paste(name, train$direction)]]
        if (!is.null(signal)) pass_signal(simulation, train, signal)
        stop <- train$awaiting_departure
        if (!is.null(stop) && stop$section == name) {
            log_event(simulation, paste("DEPART", train$name, name))
            stop$departure <- simulation$time
            train$awaiting_departure <- NULL
        }
        following <- beyond(simulation$layout, name, train$direction)
        if (following$kind == "boundary") {
            train$boundary <- following$name
            train$boundary_coordinate <- endpoint
        } else {
            name <- following$name
            start <- endpoint
            train$path[[length(train$path) + 1L]] <- list(name = name, start = start)
        }
    }
}

after_movement <- function(simulation, train, speed, previous_speed) {
    train$speed <- speed
    train$distance <- train$distance + speed
    train$maximum_speed <- max(train$maximum_speed, speed)
    if (speed == 0L) train$emergency <- FALSE
    head <- head_section(train)
    stop <- next_stop(train)
    arrived <- !is.null(stop) && speed == 0L && head$name == stop$section && train$head == head$start + simulation$layout$sections[[head$name]]$length
    if (arrived) {
        train$dwelling <- TRUE
        stop$arrival <- simulation$time
        log_event(simulation, paste("ARRIVE", train$name, head$name))
    }
    if (speed == 0L && !arrived) {
        train$standing <- train$standing + 1L
        if (previous_speed > 0L) log_event(simulation, paste("HOLD", train$name, head$name))
    }
    if (nzchar(train$boundary) && train$head - train$length >= train$boundary_coordinate) {
        train$state <- "EXITED"
        train$exited <- simulation$time
        log_event(simulation, paste("EXIT", train$name, train$boundary))
    }
}

run_trains <- function(simulation) {
    entered_boundaries <- new.env(parent = emptyenv())
    for (train in simulation$trains) {
        if (!enter_train(simulation, train, entered_boundaries)) next
        if (!finish_dwell(simulation, train)) next
        distance <- limit_distance(simulation, train)
        previous_speed <- train$speed
        speed <- select_speed(train, distance)
        move_train(simulation, train, speed)
        after_movement(simulation, train, speed, previous_speed)
    }
}

recompute_occupancy <- function(simulation) {
    for (section in simulation$layout$sections) section$occupants <- character()
    for (train in simulation$trains) {
        for (part in occupied_parts(simulation, train)) {
            section <- simulation$layout$sections[[part$name]]
            section$occupants <- union(section$occupants, train$name)
        }
    }
}

sectional_release <- function(simulation) {
    for (route in simulation$routes) {
        if (route$state != "USED") next
        remaining <- route$sections[vapply(
            route$sections,
            function(name) simulation$layout$sections[[name]]$route_lock == route$name,
            FALSE
        )]
        for (name in remaining) if (track_occupied(simulation, name)) route$passed <- union(
            route$passed,
            name
        )
        for (name in remaining) {
            if (!name %in% route$passed || track_occupied(simulation, name)) break
            unlock_section(simulation$layout, route, name)
            log_event(simulation, paste("RELEASE", route$name, name))
        }
        if (!any(vapply(
            route$sections,
            function(name) simulation$layout$sections[[name]]$route_lock == route$name,
            FALSE
        ))) {
            release_route(simulation$layout, route)
            log_event(simulation, paste("DONE", route$name))
        } else if (length(route$overlap) && route$overlap_locked) {
            route$overlap_counter <- if (track_occupied(
                simulation,
                tail(route$sections, 1L)
            )) route$overlap_counter + 1L else 0L
            if (route$overlap_counter >= simulation$overlap_time) {
                unlock_overlap(simulation$layout, route)
                log_event(simulation, paste("OVERLAP", route$name))
            }
        }
    }
}

record_statistics <- function(simulation) {
    for (route in simulation$routes) route$locked_seconds <- route$locked_seconds + as.integer(nzchar(route$state))
    for (point in simulation$layout$points) {
        point$locked_seconds <- point$locked_seconds + as.integer(length(point$locks) > 0L)
        point$moving_seconds <- point$moving_seconds + as.integer(point$moving)
    }
    for (section in simulation$layout$sections) {
        section$occupied_seconds <- section$occupied_seconds + as.integer(track_occupied(
            simulation,
            section$name
        ))
        section$locked_seconds <- section$locked_seconds + as.integer(nzchar(section$route_lock) || length(section$overlap_locks) > 0L)
        section$trains <- union(section$trains, section$occupants)
    }
    for (signal in simulation$layout$signals) signal$seconds[signal$aspect] <- signal$seconds[signal$aspect] + 1L
}

diagram <- function(simulation) {
    layout <- simulation$layout
    rows <- vapply(layout$sections, function(section) section$row, 0L)
    columns <- vapply(layout$sections, function(section) section$last, 0L)
    symbols <- c(layout$points, layout$signals, layout$buffers)
    rows <- c(
        rows,
        vapply(symbols, function(item) item$row, 0L),
        vapply(layout$labels, function(label) label$row, 0L)
    )
    columns <- c(
        columns,
        vapply(symbols, function(item) item$column, 0L),
        vapply(layout$labels, function(label) label$column + nchar(label$text) - 1L, 0L)
    )
    grid <- matrix(" ", max(rows) + 1L, max(columns) + 1L)
    for (label in layout$labels) {
        text <- strsplit(label$text, "", fixed = TRUE)[[1L]]
        for (offset in seq_along(text)) grid[label$row + 1L, label$column + offset] <- text[offset]
    }
    for (section in layout$sections) {
        character <- if (section$failed) "#" else if (nzchar(section$route_lock)) "=" else if (length(section$overlap_locks)) "~" else "-"
        grid[section$row + 1L, (section$first + 1L):(section$last + 1L)] <- character
    }
    for (train in simulation$trains) {
        for (part in occupied_parts(simulation, train)) {
            section <- layout$sections[[part$name]]
            span <- section$length
            cells <- section$last - section$first + 1L
            if (train$direction == "UP") {
                left <- part$low - part$start
                right <- part$high - part$start
            } else {
                left <- span - (part$high - part$start)
                right <- span - (part$low - part$start)
            }
            for (cell in seq_len(cells) - 1L) {
                if (left * cells < (cell + 1L) * span && right * cells > cell * span) {
                    column <- section$first + cell + 1L
                    previous <- grid[section$row + 1L, column]
                    grid[
                        section$row + 1L,
                        column
                    ] <- if (previous %in% c(letters, "*")) "*" else train$symbol
                }
            }
        }
    }
    for (buffer in layout$buffers) grid[buffer$row + 1L, buffer$column + 1L] <- "|"
    for (point in layout$points) grid[
        point$row + 1L,
        point$column + 1L
    ] <- if (point_detected(point)) point$position else "?"
    for (signal in layout$signals) grid[signal$row + 1L, signal$column + 1L] <- c(
        RED = "X",
        YELLOW = "Y",
        GREEN = "G"
    )[[signal$aspect]]
    vapply(seq_len(nrow(grid)), function(row) sub(" +$", "", paste0(grid[row, ], collapse = "")), "")
}

snapshot <- function(simulation) {
    lines <- c(paste("SNAPSHOT", simulation$time), diagram(simulation))
    for (train in simulation$trains) {
        if (train$state == "RUNNING") {
            sections <- paste(
                vapply(occupied_parts(simulation, train), function(part) part$name, ""),
                collapse = ","
            )
            lines <- c(
                lines,
                paste("TRAIN", train$symbol, train$name, train$direction, train$speed, sections)
            )
        }
    }
    routes <- vapply(
        Filter(function(route) nzchar(route$state), simulation$routes),
        function(route) paste0(route$name, "/", route$state),
        ""
    )
    c(lines, paste("ROUTES", if (length(routes)) paste(routes, collapse = " ") else "-"))
}

train_rows <- function(simulation) {
    rows <- list()
    for (train in simulation$trains) {
        rows[[length(rows) + 1L]] <- list(
            name = train$name,
            location = paste0("enter:", train$entry),
            scheduled = train$entry_time,
            actual = train$entered
        )
        for (stop in train$stops) {
            rows[[length(rows) + 1L]] <- list(
                name = train$name,
                location = paste0("arr:", stop$section),
                scheduled = stop$scheduled_arrival,
                actual = stop$arrival
            )
            rows[[length(rows) + 1L]] <- list(
                name = train$name,
                location = paste0("dep:", stop$section),
                scheduled = stop$scheduled_departure,
                actual = stop$departure
            )
        }
        rows[[length(rows) + 1L]] <- list(
            name = train$name,
            location = paste0("exit:", train$exit),
            scheduled = train$scheduled_exit,
            actual = train$exited
        )
    }
    rows
}

train_report <- function(rows) {
    c("train,location,scheduled,actual,delay", vapply(rows, function(row) {
        timing <- if (row$actual < 0L) "-,-" else paste0(row$actual, ",", row$actual - row$scheduled)
        sprintf("%s,%s,%d,%s", row$name, row$location, row$scheduled, timing)
    }, ""))
}

punctuality <- function(rows) {
    on_time <- late <- missing <- total_delay <- maximum_delay <- 0L
    for (row in rows) {
        if (row$actual < 0L) {
            missing <- missing + 1L
        } else if (row$actual <= row$scheduled) {
            on_time <- on_time + 1L
        } else {
            late <- late + 1L
            total_delay <- total_delay + row$actual - row$scheduled
            maximum_delay <- max(maximum_delay, row$actual - row$scheduled)
        }
    }
    sprintf(
        "PUNCTUALITY on_time %d late %d missing %d total_delay %d max_delay %d",
        on_time,
        late,
        missing,
        total_delay,
        maximum_delay
    )
}

summary_lines <- function(simulation, rows) {
    lines <- character()
    for (route in simulation$routes) lines <- c(
        lines,
        sprintf(
            "ROUTE %s %s-%s requests %d grants %d uses %d cancels %d wait %d maxwait %d locked %d",
            route$name,
            route$start,
            route$finish,
            route$requests,
            route$grants,
            route$uses,
            route$cancels,
            route$wait,
            route$maxwait,
            route$locked_seconds
        )
    )
    for (point in simulation$layout$points) lines <- c(
        lines,
        sprintf(
            "POINT %s throws %d locked %d moving %d final %s",
            point$name,
            point$throws,
            point$locked_seconds,
            point$moving_seconds,
            if (point_detected(point)) point$position else "?"
        )
    )
    for (section in simulation$layout$sections) lines <- c(
        lines,
        sprintf(
            "SECTION %s occupied %d locked %d trains %d",
            section$name,
            section$occupied_seconds,
            section$locked_seconds,
            length(section$trains)
        )
    )
    for (signal in simulation$layout$signals) lines <- c(
        lines,
        sprintf(
            "SIGNAL %s red %d yellow %d green %d passes %d",
            signal$name,
            signal$seconds[["RED"]],
            signal$seconds[["YELLOW"]],
            signal$seconds[["GREEN"]],
            signal$passes
        )
    )
    for (train in simulation$trains) lines <- c(
        lines,
        sprintf(
            "TRAIN %s %s %s distance %d maxspeed %d standing %d passes %d",
            train$name,
            train$symbol,
            train$state,
            train$distance,
            train$maximum_speed,
            train$standing,
            train$passes
        )
    )
    states <- vapply(simulation$trains, function(train) train$state, "")
    lines <- c(
        lines,
        sprintf(
            "TRAINS total %d exited %d running %d waiting %d",
            length(states),
            sum(states == "EXITED"),
            sum(states == "RUNNING"),
            sum(states == "WAITING")
        ),
        punctuality(rows)
    )
    grants <- sum(vapply(simulation$routes, function(route) route$grants, 0L))
    c(
        lines,
        sprintf(
            "REQUESTS total %d granted %d dropped %d pending %d",
            simulation$request_count,
            grants,
            simulation$dropped,
            length(simulation$queue)
        )
    )
}

main <- function() {
    simulation <- read_simulation()
    for (time in 0L:simulation$end_time) {
        simulation$time <- time
        complete_throws(simulation)
        release_approaches(simulation)
        for (request in simulation$planned[[as.character(time)]]) add_request(
            simulation,
            request$route,
            request$train
        )
        execute_events(simulation)
        judge_requests(simulation)
        decide_signals(simulation)
        run_trains(simulation)
        recompute_occupancy(simulation)
        sectional_release(simulation)
        inspect_safety(simulation$safety, time, simulation$layout, simulation$routes)
        record_statistics(simulation)
        if (time %in% simulation$snapshot_times) simulation$snapshots <- c(
            simulation$snapshots,
            snapshot(simulation)
        )
    }
    rows <- train_rows(simulation)
    reports <- list(
        events.txt = simulation$log_lines,
        snapshots.txt = simulation$snapshots,
        train_log.csv = train_report(rows),
        safety.txt = safety_report(simulation$safety),
        summary.txt = summary_lines(simulation, rows)
    )
    dir.create("output", showWarnings = FALSE)
    for (name in names(reports)) writeLines(reports[[name]], file.path("output", name), useBytes = TRUE)
}

main()
