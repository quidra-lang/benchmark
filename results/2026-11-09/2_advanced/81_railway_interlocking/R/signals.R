signal_aspects <- function(layout, routes, occupied) {
    cleared <- setNames(rep(list(NULL), length(layout$signals)), names(layout$signals))
    for (signal in layout$signals) {
        for (route in routes) {
            if (route$start != signal$name || route$state != "LOCKED") next
            ready <- all(vapply(
                route$requirements,
                function(entry) point_detected(layout$points[[entry$name]]) && layout$points[[entry$name]]$position == entry$position,
                FALSE
            ))
            if (!ready) next
            if (!any(vapply(c(route$sections, route$overlap), occupied, FALSE))) {
                cleared[[signal$name]] <- route
                break
            }
        }
    }
    lapply(layout$signals, function(signal) {
        route <- cleared[[signal$name]]
        if (is.null(route)) {
            aspect <- "RED"
        } else if (route$finish %in% names(layout$signals)) {
            aspect <- if (is.null(cleared[[route$finish]])) "YELLOW" else "GREEN"
        } else {
            aspect <- if (route$finish %in% names(layout$buffers)) "YELLOW" else "GREEN"
        }
        list(signal = signal, aspect = aspect)
    })
}
