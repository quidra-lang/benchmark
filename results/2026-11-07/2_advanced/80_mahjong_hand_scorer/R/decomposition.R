DECOMPOSITION_CACHE <- new.env(parent = emptyenv())

standard_decompositions <- function(counts, meld_count = 0L) {
    key <- paste0(paste0(counts, collapse = ""), ":", meld_count)
    if (exists(key, DECOMPOSITION_CACHE, inherits = FALSE)) return(DECOMPOSITION_CACHE[[key]])
    needed <- 4L - meld_count
    if (sum(counts) != 3L * needed + 2L) return(list())
    remaining <- counts
    found <- new.env(parent = emptyenv())
    visit <- function(pair, sets) {
        if (length(sets) == needed) {
            if (all(remaining == 0L)) {
                if (length(sets)) sets <- sets[order(
                    vapply(sets, function(block) block[1L], 0L),
                    vapply(sets, function(block) block[1L] != tail(block, 1L), FALSE)
                )]
                signature <- paste0(
                    pair,
                    ":",
                    paste(vapply(sets, function(block) paste(block, collapse = ","), ""), collapse = ";")
                )
                found[[signature]] <- list(pair = pair, sets = sets)
            }
            return(invisible(NULL))
        }
        occupied <- which(remaining > 0L)
        if (!length(occupied)) return(invisible(NULL))
        first <- occupied[1L]
        kind <- first - 1L
        if (remaining[first] >= 3L) {
            remaining[first] <<- remaining[first] - 3L
            visit(pair, c(sets, list(rep(kind, 3L))))
            remaining[first] <<- remaining[first] + 3L
        }
        if (kind < 27L && kind %% 9L <= 6L && remaining[first + 1L] > 0L && remaining[first + 2L] > 0L) {
            indices <- first:(first + 2L)
            remaining[indices] <<- remaining[indices] - 1L
            visit(pair, c(sets, list(kind:(kind + 2L))))
            remaining[indices] <<- remaining[indices] + 1L
        }
    }
    for (pair in 0:33) {
        if (remaining[pair + 1L] >= 2L) {
            remaining[pair + 1L] <- remaining[pair + 1L] - 2L
            visit(pair, list())
            remaining[pair + 1L] <- remaining[pair + 1L] + 2L
        }
    }
    result <- unname(as.list(found))
    DECOMPOSITION_CACHE[[key]] <- result
    result
}

seven_pairs <- function(counts) sum(counts == 2L) == 7L && all(counts %in% c(0L, 2L))
thirteen_orphans <- function(counts) sum(counts) == 14L && all(counts[YAOCHUU + 1L] > 0L) && all(counts[setdiff(
    0:33,
    YAOCHUU
) + 1L] == 0L)
winning_form <- function(
    counts,
    meld_count = 0L
) length(standard_decompositions(
    counts,
    meld_count
)) > 0L || (meld_count == 0L && (seven_pairs(counts) || thirteen_orphans(counts)))

waiting_tiles <- function(hand_counts, meld_counts, meld_count) {
    waiting <- integer()
    concealed <- hand_counts
    for (kind in 0:33) {
        if (hand_counts[kind + 1L] + meld_counts[kind + 1L] >= 4L) next
        concealed[kind + 1L] <- concealed[kind + 1L] + 1L
        if (winning_form(concealed, meld_count)) waiting <- c(waiting, kind)
        concealed[kind + 1L] <- concealed[kind + 1L] - 1L
    }
    waiting
}

wait_shape <- function(form, block, winning_tile, hand_counts) {
    if (form == "chiitoitsu") return("tanki")
    if (form == "kokushi") return(if (all(hand_counts[YAOCHUU + 1L] == 1L)) "thirteen" else "single")
    if (length(block) == 2L) return("tanki")
    if (block[1L] == tail(block, 1L)) return("shanpon")
    first <- block[1L]
    if (winning_tile == first + 1L) return("kanchan")
    if ((first %% 9L == 0L && winning_tile == first + 2L) || (first %% 9L == 6L && winning_tile == first)) return("penchan")
    "ryanmen"
}
