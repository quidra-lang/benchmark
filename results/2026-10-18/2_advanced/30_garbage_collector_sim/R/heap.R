heap_object <- function(number, p, d) {
    object <- new.env(parent = emptyenv())
    object$number <- number
    object$size <- 1L + p + d
    object$fields <- integer(p)
    object$address <- 0L
    object$marked <- FALSE
    object$moves <- object$age <- object$count <- 0L
    object
}
object_pair <- function(objects) c(length(objects), sum(vapply(objects, function(object) object$size, 0L)))
pair_text <- function(pair) paste(pair, collapse = " ")
add_object <- function(record, field, object) record[[field]] <- record[[field]] + c(1L, object$size)
collection_record <- function(number, line, request, kind, blocks) {
    record <- new.env(parent = emptyenv())
    record$number <- number
    record$line <- line
    record$request <- request
    record$kind <- kind
    record$live <- record$freed <- record$moved <- record$promoted <- c(0L, 0L)
    record$stack <- record$work <- 0L
    record$before <- c(total_free(blocks), largest_free(blocks))
    record$after <- c(0L, 0L)
    record
}
collector <- function(entry, size, deaths) {
    state <- new.env(parent = emptyenv())
    state$kind <- entry$kind
    state$size <- size
    state$young <- entry$young
    state$promotion_age <- entry$age
    state$base <- state$top <- 0L
    state$objects <- state$placed <- state$records <- state$released <- state$reports <- list()
    state$remembered <- integer()
    state$barriers <- state$remembers <- state$increments <- state$decrements <- 0L
    state$deaths <- deaths
    state
}
by_address <- function(objects) objects[order(vapply(objects, function(object) object$address, 0L))]
free_blocks <- function(objects, start, end) {
    blocks <- list()
    position <- start
    for (object in by_address(objects)) {
        if (object$address < start || object$address >= end) next
        if (object$address > position) blocks <- c(blocks, list(c(position, object$address - position)))
        position <- object$address + object$size
    }
    if (position < end) blocks <- c(blocks, list(c(position, end - position)))
    blocks
}
first_fit <- function(blocks, size) {
    for (block in blocks) if (block[2L] >= size) return(block[1L])
    NULL
}
total_free <- function(blocks) sum(vapply(blocks, function(block) block[2L], 0L))
largest_free <- function(blocks) max(c(0L, vapply(blocks, function(block) block[2L], 0L)))
is_young <- function(state, object) object$address < state$young
old_blocks <- function(state) free_blocks(state$objects, state$young, state$size)
free_list <- function(state) {
    if (state$kind %in% c("MARK_SWEEP", "REFCOUNT")) return(free_blocks(state$objects, 0L, state$size))
    end <- if (state$kind == "MARK_COMPACT") state$size else state$base + (if (state$kind == "COPYING") state$size else state$young) %/% 2L
    blocks <- if (state$top < end) list(c(state$top, end - state$top)) else list()
    if (state$kind == "GENERATIONAL") c(blocks, old_blocks(state)) else blocks
}
inactive_range <- function(state) {
    if (!(state$kind %in% c("COPYING", "GENERATIONAL"))) return(c(0L, 0L))
    half <- (if (state$kind == "COPYING") state$size else state$young) %/% 2L
    start <- half - state$base
    c(start, start + half)
}
finish_record <- function(state, record) {
    blocks <- free_list(state)
    record$after <- c(total_free(blocks), largest_free(blocks))
    state$records <- c(state$records, list(record))
}
dec2 <- function(a, b) {
    q <- (200L * a + b) %/% (2L * b)
    paste0(q %/% 100L, ".", sprintf("%02d", q %% 100L))
}
pct <- function(a, b) if (b == 0L) "-" else dec2(100L * a, b)
fragmentation <- function(blocks) pct(total_free(blocks) - largest_free(blocks), total_free(blocks))
class_table <- function(values) {
    counts <- integer(5L)
    for (value in values) {
        index <- which(value <= c(1L, 3L, 7L, 15L))
        index <- if (length(index)) index[1L] else 5L
        counts[index] <- counts[index] + 1L
    }
    paste(paste(c("1", "2-3", "4-7", "8-15", "16+"), counts, sep = ":"), collapse = " ")
}
heap_map <- function(size, objects, reachable, inactive) {
    cells <- rep(".", size)
    if (inactive[2L] > inactive[1L]) cells[seq.int(inactive[1L] + 1L, inactive[2L])] <- "-"
    for (object in objects) {
        letter <- LETTERS[(object$number - 1L) %% 26L + 1L]
        header <- if (object$number %in% reachable) letter else "#"
        body <- if (object$number %in% reachable) tolower(letter) else "="
        cells[object$address + 1L] <- header
        if (object$size > 1L) cells[seq.int(object$address + 2L, object$address + object$size)] <- body
    }
    paste(cells, collapse = "")
}
