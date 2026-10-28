next_stop <- function(train) if (train$stop_index <= length(train$stops)) train$stops[[train$stop_index]] else NULL

read_trains <- function() {
    trains <- requests <- list()
    for (line in readLines("input/trains.txt", warn = FALSE)) {
        fields <- strsplit(line, " ", fixed = TRUE)[[1L]]
        kind <- fields[1L]
        values <- fields[-1L]
        if (kind == "TRAIN") {
            train <- new.env(parent = emptyenv())
            train$name <- values[1L]
            train$symbol <- intToUtf8(utf8ToInt("a") + length(trains))
            for (index in 2:5) train[[c(
                "length",
                "acceleration",
                "deceleration",
                "max_speed"
            )[index - 1L]]] <- as.integer(values[index])
            train$entry <- values[6L]
            train$entry_time <- as.integer(values[7L])
            train$entry_speed <- as.integer(values[8L])
            train$exit <- ""
            train$scheduled_exit <- 0L
            train$stops <- list()
            train$stop_index <- 1L
            train$state <- "WAITING"
            train$direction <- ""
            train$path <- list()
            train$head <- train$speed <- 0L
            train$dwelling <- train$emergency <- FALSE
            train$awaiting_departure <- NULL
            train$boundary <- ""
            train$boundary_coordinate <- 0L
            train$entered <- train$exited <- -1L
            train$distance <- train$maximum_speed <- train$standing <- train$passes <- 0L
            trains[[train$name]] <- train
        } else if (kind == "REQUEST") {
            requests[[length(requests) + 1L]] <- list(
                time = as.integer(values[3L]),
                train = values[1L],
                route = values[2L]
            )
        } else if (kind %in% c("STOP", "TURN")) {
            stop <- new.env(parent = emptyenv())
            stop$kind <- kind
            stop$section <- values[2L]
            stop$dwell <- as.integer(values[3L])
            stop$scheduled_arrival <- as.integer(values[4L])
            stop$scheduled_departure <- as.integer(values[5L])
            stop$arrival <- stop$departure <- -1L
            train <- trains[[values[1L]]]
            train$stops[[length(train$stops) + 1L]] <- stop
        } else {
            trains[[values[1L]]]$exit <- values[2L]
            trains[[values[1L]]]$scheduled_exit <- as.integer(values[3L])
        }
    }
    list(trains = trains, requests = requests)
}

braking_distance <- function(speed, deceleration) {
    count <- speed %/% deceleration
    count * speed - (deceleration * count * (count + 1L)) %/% 2L
}

select_speed <- function(train, distance) {
    low <- max(train$speed - train$deceleration, 0L)
    if (!train$emergency) {
        for (speed in seq.int(min(train$speed + train$acceleration, train$max_speed), low)) {
            if (is.null(distance) || speed + braking_distance(
                speed,
                train$deceleration
            ) <= distance) return(speed)
        }
    }
    low
}
