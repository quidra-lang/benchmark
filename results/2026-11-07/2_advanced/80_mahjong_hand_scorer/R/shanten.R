SHANTEN_PATTERN_CACHE <- new.env(parent = emptyenv())
SHANTEN_NUMBER_CACHE <- new.env(parent = emptyenv())

shanten_patterns <- function(counts, suited) {
    key <- paste0(as.integer(suited), ":", paste0(counts, collapse = ""))
    if (exists(key, SHANTEN_PATTERN_CACHE, inherits = FALSE)) return(SHANTEN_PATTERN_CACHE[[key]])
    occupied <- which(counts > 0L)
    if (!length(occupied)) return(list(c(0L, 0L, 0L)))
    first <- occupied[1L]
    choices <- list(list(removed = first, extra = c(0L, 0L, 0L)))
    if (counts[first] >= 3L) choices <- c(
        choices,
        list(list(removed = rep(first, 3L), extra = c(1L, 0L, 0L)))
    )
    if (counts[first] >= 2L) choices <- c(
        choices,
        list(
            list(removed = rep(first, 2L), extra = c(0L, 1L, 0L)),
            list(removed = rep(first, 2L), extra = c(0L, 0L, 1L))
        )
    )
    if (suited) {
        if (first <= 7L && counts[first + 1L] > 0L && counts[first + 2L] > 0L) choices <- c(
            choices,
            list(list(removed = first:(first + 2L), extra = c(1L, 0L, 0L)))
        )
        for (difference in c(1L, 2L)) {
            other <- first + difference
            if (other <= 9L && counts[other] > 0L) choices <- c(
                choices,
                list(list(removed = c(first, other), extra = c(0L, 1L, 0L)))
            )
        }
    }
    best <- matrix(-1L, 5L, 2L)
    for (choice in choices) {
        remaining <- counts
        for (index in choice$removed) remaining[index] <- remaining[index] - 1L
        for (pattern in shanten_patterns(remaining, suited)) {
            pattern <- pattern + choice$extra
            sets <- pattern[1L]
            pair <- pattern[3L]
            if (sets > 4L || pair > 1L) next
            best[sets + 1L, pair + 1L] <- max(best[sets + 1L, pair + 1L], min(4L, pattern[2L]))
        }
    }
    result <- list()
    for (sets in 0:4) for (pair in 0:1) {
        if (best[sets + 1L, pair + 1L] >= 0L) result[[length(result) + 1L]] <- c(
            sets,
            best[sets + 1L, pair + 1L],
            pair
        )
    }
    SHANTEN_PATTERN_CACHE[[key]] <- result
    result
}

standard_shanten <- function(counts) {
    states <- list(c(0L, 0L, 0L))
    for (bounds in list(c(1L, 9L), c(10L, 18L), c(19L, 27L), c(28L, 34L))) {
        local <- shanten_patterns(counts[bounds[1L]:bounds[2L]], bounds[1L] < 28L)
        combined <- matrix(-1L, 5L, 2L)
        for (state in states) for (pattern in local) {
            merged <- state + pattern
            sets <- merged[1L]
            pair <- merged[3L]
            if (sets > 4L || pair > 1L) next
            combined[sets + 1L, pair + 1L] <- max(combined[sets + 1L, pair + 1L], min(4L, merged[2L]))
        }
        states <- list()
        for (sets in 0:4) for (pair in 0:1) {
            if (combined[sets + 1L, pair + 1L] >= 0L) states[[length(states) + 1L]] <- c(
                sets,
                combined[sets + 1L, pair + 1L],
                pair
            )
        }
    }
    min(vapply(states, function(state) 8L - 2L * state[1L] - min(state[2L], 4L - state[1L]) - state[3L], 0L))
}

shanten_numbers <- function(counts) {
    key <- paste0(counts, collapse = "")
    if (!exists(key, SHANTEN_NUMBER_CACHE, inherits = FALSE)) {
        seven <- 6L - sum(counts >= 2L) + max(0L, 7L - sum(counts >= 1L))
        orphans <- 13L - sum(counts[YAOCHUU + 1L] >= 1L) - as.integer(any(counts[YAOCHUU + 1L] >= 2L))
        SHANTEN_NUMBER_CACHE[[key]] <- c(standard_shanten(counts), seven, orphans)
    }
    SHANTEN_NUMBER_CACHE[[key]]
}
