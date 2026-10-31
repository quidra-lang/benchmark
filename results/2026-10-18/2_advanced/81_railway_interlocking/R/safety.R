SAFETY_PROPERTIES <- c("OCCUPANCY", "POINT_MOTION", "CONFLICT", "SIGNAL_PASSING")
new_safety <- function() {
    safety <- new.env(parent = emptyenv())
    safety$checks <- safety$violations <- setNames(integer(4L), SAFETY_PROPERTIES)
    safety$records <- character()
    safety
}

safety_check <- function(safety, time, kind, details = NULL) {
    safety$checks[kind] <- safety$checks[kind] + 1L
    if (!is.null(details)) {
        safety$violations[kind] <- safety$violations[kind] + 1L
        safety$records <- c(safety$records, paste("VIOLATION", time, kind, details))
    }
}

inspect_safety <- function(safety, time, layout, routes) {
    for (section in layout$sections) {
        details <- if (length(section$occupants) >= 2L) paste(
            section$name,
            paste(section$occupants, collapse = ",")
        ) else NULL
        safety_check(safety, time, "OCCUPANCY", details)
    }
    for (point in layout$points) {
        if (point$moving) {
            details <- NULL
            if (length(layout$sections[[point$common]]$occupants)) details <- paste(
                point$name,
                "occupied"
            ) else if (any(vapply(
                point$locks,
                function(lock) routes[[lock$route]]$state %in% c("USED", "APPROACH"),
                FALSE
            ))) details <- paste(point$name, "locked")
            safety_check(safety, time, "POINT_MOTION", details)
        }
    }
    locked <- Filter(function(route) route$state %in% c("LOCKED", "APPROACH"), routes)
    for (first_index in seq_along(locked)) {
        if (first_index >= length(locked)) next
        for (second_index in seq.int(first_index + 1L, length(locked))) {
            first <- locked[[first_index]]
            second <- locked[[second_index]]
            conflict <- second$name %in% first$conflicts || first$name %in% second$conflicts
            safety_check(safety, time, "CONFLICT", if (conflict) paste(first$name, second$name) else NULL)
        }
    }
}

safety_report <- function(safety) {
    lines <- vapply(
        SAFETY_PROPERTIES,
        function(kind) sprintf(
            "%s %s checks %d violations %d",
            kind,
            if (safety$violations[[kind]] == 0L) "OK" else "FAIL",
            safety$checks[[kind]],
            safety$violations[[kind]]
        ),
        ""
    )
    c(lines, safety$records, paste("RESULT", if (length(safety$records)) "UNSAFE" else "SAFE"))
}
