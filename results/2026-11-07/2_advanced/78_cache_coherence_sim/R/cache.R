new_cache <- function(sets, ways, replacement) {
    cache <- new.env(parent = emptyenv())
    cache$number_sets <- sets
    cache$ways <- ways
    cache$replacement <- replacement
    cache$blocks <- matrix(-1L, sets, ways)
    cache$states <- matrix("I", sets, ways)
    cache$touched <- matrix(0L, sets, ways)
    cache$bits <- matrix(0L, sets, ways - 1L)
    cache$fills <- cache$evictions <- integer(sets)
    cache$clock <- 0L
    cache
}

cache_locate <- function(cache, block) {
    row <- block %% cache$number_sets + 1L
    way <- match(block, cache$blocks[row, ])
    if (is.na(way)) NULL else c(row, way)
}

cache_state <- function(cache, block) {
    place <- cache_locate(cache, block)
    if (is.null(place)) "I" else cache$states[place[1L], place[2L]]
}

cache_change <- function(cache, block, state) {
    place <- cache_locate(cache, block)
    if (!is.null(place)) cache$states[place[1L], place[2L]] <- state
}

cache_touch_way <- function(cache, row, way, filling = FALSE) {
    if (cache$replacement == "LRU" || (cache$replacement == "FIFO" && filling)) {
        cache$clock <- cache$clock + 1L
        cache$touched[row, way] <- cache$clock
    } else if (cache$replacement == "PLRU") {
        low <- 0L
        high <- cache$ways
        node <- 1L
        while (high - low > 1L) {
            middle <- (low + high) %/% 2L
            if (way - 1L < middle) {
                cache$bits[row, node] <- 1L
                high <- middle
                node <- node * 2L
            } else {
                cache$bits[row, node] <- 0L
                low <- middle
                node <- node * 2L + 1L
            }
        }
    }
}

cache_touch <- function(cache, block) {
    place <- cache_locate(cache, block)
    if (!is.null(place)) cache_touch_way(cache, place[1L], place[2L])
}

cache_victim <- function(cache, row) {
    if (cache$replacement == "PLRU") {
        low <- 0L
        high <- cache$ways
        node <- 1L
        while (high - low > 1L) {
            middle <- (low + high) %/% 2L
            if (cache$bits[row, node] == 0L) {
                high <- middle
                node <- node * 2L
            } else {
                low <- middle
                node <- node * 2L + 1L
            }
        }
        return(low + 1L)
    }
    which.min(cache$touched[row, ])
}

cache_fill <- function(cache, block, state) {
    row <- block %% cache$number_sets + 1L
    empty <- which(cache$blocks[row, ] == -1L)
    way <- if (length(empty)) empty[1L] else cache_victim(cache, row)
    victim <- if (cache$blocks[row, way] == -1L) NULL else list(
        block = cache$blocks[row, way],
        state = cache$states[row, way]
    )
    if (!is.null(victim)) cache$evictions[row] <- cache$evictions[row] + 1L
    cache$blocks[row, way] <- block
    cache$states[row, way] <- state
    cache$fills[row] <- cache$fills[row] + 1L
    cache_touch_way(cache, row, way, TRUE)
    victim
}

cache_remove <- function(cache, block) {
    place <- cache_locate(cache, block)
    if (is.null(place)) return(NULL)
    old <- list(block = block, state = cache$states[place[1L], place[2L]])
    cache$blocks[place[1L], place[2L]] <- -1L
    cache$states[place[1L], place[2L]] <- "I"
    old
}

cache_order <- function(cache, row) {
    if (cache$replacement == "PLRU") return(if (cache$ways == 1L) "-" else paste0(
        cache$bits[row, ],
        collapse = ""
    ))
    active <- which(cache$blocks[row, ] != -1L)
    active <- active[order(-cache$touched[row, active], active)]
    if (length(active)) paste(active - 1L, collapse = " ") else "-"
}

cache_lines <- function(cache) {
    entries <- list()
    for (row in seq_len(cache$number_sets)) for (way in seq_len(cache$ways)) {
        if (cache$blocks[row, way] != -1L) entries[[length(entries) + 1L]] <- list(
            block = cache$blocks[row, way],
            state = cache$states[row, way]
        )
    }
    entries
}
