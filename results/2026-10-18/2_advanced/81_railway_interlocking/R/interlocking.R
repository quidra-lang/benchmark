route_names <- function(text) if (text == "-") character() else strsplit(text, ",", fixed = TRUE)[[1L]]

read_routes <- function(layout) {
    routes <- list()
    for (line in readLines("input/routes.txt", warn = FALSE)) {
        fields <- strsplit(line, " ", fixed = TRUE)[[1L]][-1L]
        route <- new.env(parent = emptyenv())
        route$name <- fields[1L]
        route$start <- fields[2L]
        route$finish <- fields[3L]
        route$requirements <- list()
        for (text in fields[c(4L, 7L)]) for (item in route_names(text)) {
            parts <- strsplit(item, ":", fixed = TRUE)[[1L]]
            route$requirements[[length(route$requirements) + 1L]] <- list(
                name = parts[1L],
                position = parts[2L]
            )
        }
        route$sections <- route_names(fields[5L])
        route$overlap <- route_names(fields[6L])
        route$conflicts <- route_names(fields[8L])
        route$approach_time <- as.integer(fields[9L])
        route$direction <- layout$signals[[route$start]]$direction
        route$state <- ""
        route$release_time <- -1L
        route$passed <- character()
        route$overlap_locked <- FALSE
        route$overlap_counter <- 0L
        route$requests <- route$grants <- route$uses <- route$cancels <- 0L
        route$wait <- route$maxwait <- route$locked_seconds <- 0L
        routes[[route$name]] <- route
    }
    routes
}

lock_route <- function(layout, route) {
    route$state <- "LOCKED"
    route$release_time <- -1L
    route$passed <- character()
    route$overlap_locked <- TRUE
    route$overlap_counter <- 0L
    for (name in route$sections) layout$sections[[name]]$route_lock <- route$name
    for (name in route$overlap) layout$sections[[name]]$overlap_locks <- union(
        layout$sections[[name]]$overlap_locks,
        route$name
    )
    for (entry in route$requirements) layout$points[[entry$name]]$locks[[paste(
        route$name,
        entry$position
    )]] <- list(
        route = route$name,
        position = entry$position
    )
}

unlock_points <- function(layout, route, sections = NULL) {
    for (point in layout$points) {
        if (is.null(sections) || point$common %in% sections) point$locks <- Filter(
            function(lock) lock$route != route$name,
            point$locks
        )
    }
}

unlock_section <- function(layout, route, name) {
    section <- layout$sections[[name]]
    if (section$route_lock == route$name) section$route_lock <- ""
    unlock_points(layout, route, name)
}

unlock_overlap <- function(layout, route) {
    for (name in route$overlap) layout$sections[[name]]$overlap_locks <- setdiff(
        layout$sections[[name]]$overlap_locks,
        route$name
    )
    unlock_points(layout, route, route$overlap)
    route$overlap_locked <- FALSE
}

release_route <- function(layout, route) {
    for (name in route$sections) if (layout$sections[[name]]$route_lock == route$name) layout$sections[[name]]$route_lock <- ""
    if (route$overlap_locked) unlock_overlap(layout, route)
    unlock_points(layout, route)
    route$state <- ""
    route$release_time <- -1L
}
