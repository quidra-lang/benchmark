point_detected <- function(point) !point$moving && !point$failed

read_layout <- function() {
    layout <- new.env(parent = emptyenv())
    layout$sections <- layout$points <- layout$signals <- layout$buffers <- layout$boundaries <- list()
    layout$labels <- list()
    layout$ends <- new.env(parent = emptyenv())
    layout$signals_at <- new.env(parent = emptyenv())
    for (line in readLines("input/layout.txt", warn = FALSE)) {
        fields <- strsplit(line, " ", fixed = TRUE)[[1L]]
        kind <- fields[1L]
        values <- fields[-1L]
        name <- values[1L]
        if (kind == "SECTION") {
            item <- new.env(parent = emptyenv())
            item$name <- name
            item$length <- as.integer(values[2L])
            item$row <- as.integer(values[3L])
            item$first <- as.integer(values[4L])
            item$last <- as.integer(values[5L])
            item$failed <- FALSE
            item$occupants <- character()
            item$occupied_seconds <- item$locked_seconds <- 0L
            item$trains <- character()
            item$route_lock <- ""
            item$overlap_locks <- character()
            layout$sections[[name]] <- item
        } else if (kind == "JOINT") {
            layout$ends[[paste(values[1L], "R")]] <- list(kind = "section", name = values[2L])
            layout$ends[[paste(values[2L], "L")]] <- list(kind = "section", name = values[1L])
        } else if (kind == "POINT") {
            item <- new.env(parent = emptyenv())
            for (index in 1:5) item[[c(
                "name",
                "side",
                "common",
                "normal",
                "reverse"
            )[index]]] <- values[index]
            item$row <- as.integer(values[6L])
            item$column <- as.integer(values[7L])
            item$position <- "N"
            item$moving <- item$failed <- FALSE
            item$target <- ""
            item$completion <- -1L
            item$throws <- item$locked_seconds <- item$moving_seconds <- 0L
            item$locks <- list()
            layout$points[[name]] <- item
            layout$ends[[paste(item$common, item$side)]] <- list(kind = "point", name = name)
            other <- if (item$side == "R") "L" else "R"
            layout$ends[[paste(item$normal, other)]] <- layout$ends[[paste(item$reverse, other)]] <- list(
                kind = "point",
                name = name
            )
        } else if (kind == "SIGNAL") {
            item <- new.env(parent = emptyenv())
            item$name <- name
            item$section <- values[2L]
            item$direction <- values[3L]
            item$row <- as.integer(values[4L])
            item$column <- as.integer(values[5L])
            item$aspect <- "RED"
            item$seconds <- c(RED = 0L, YELLOW = 0L, GREEN = 0L)
            item$passes <- 0L
            layout$signals[[name]] <- layout$signals_at[[paste(item$section, item$direction)]] <- item
        } else if (kind %in% c("BUFFER", "BOUNDARY")) {
            item <- list(name = name, section = values[2L], endpoint = values[3L])
            if (kind == "BUFFER") {
                item$row <- as.integer(values[4L])
                item$column <- as.integer(values[5L])
                layout$buffers[[name]] <- item
            } else {
                layout$boundaries[[name]] <- item
            }
            layout$ends[[paste(item$section, item$endpoint)]] <- list(kind = tolower(kind), name = name)
        } else {
            layout$labels[[length(layout$labels) + 1L]] <- list(
                row = as.integer(values[1L]),
                column = as.integer(values[2L]),
                text = values[3L]
            )
        }
    }
    layout
}

beyond <- function(layout, section, direction) {
    result <- layout$ends[[paste(section, if (direction == "UP") "R" else "L")]]
    if (result$kind != "point") return(result)
    point <- layout$points[[result$name]]
    branch <- if (point$position == "N") point$normal else point$reverse
    if (point$moving || (section != point$common && section != branch)) return(list(
        kind = "impassable",
        name = ""
    ))
    list(kind = "section", name = if (section == point$common) branch else point$common)
}
