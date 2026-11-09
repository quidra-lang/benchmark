mark <- function(record, roots, objects, placed) {
    for (object in objects) object$marked <- FALSE
    record$work <- record$work + length(roots)
    stack <- integer()
    push_mark <- function(id) {
        placed[[id]]$marked <- TRUE
        stack <<- c(stack, id)
        record$stack <- max(record$stack, length(stack))
    }
    for (root in roots) {
        if (root == 0L || placed[[root]]$marked) next
        push_mark(root)
        while (length(stack)) {
            id <- tail(stack, 1L)
            stack <- head(stack, -1L)
            object <- placed[[id]]
            add_object(record, "live", object)
            record$work <- record$work + 1L + length(object$fields)
            for (id in object$fields) if (id != 0L && !placed[[id]]$marked) push_mark(id)
        }
    }
}
sweep <- function(state, record) {
    record$work <- record$work + length(state$objects)
    for (object in state$objects) if (!object$marked) add_object(record, "freed", object)
    state$objects <- Filter(function(object) object$marked, state$objects)
}
collect_sweep <- function(state, roots, line, request) {
    record <- collection_record(length(state$records) + 1L, line, request, "sweep", free_list(state))
    mark(record, roots, state$objects, state$placed)
    sweep(state, record)
    finish_record(state, record)
}
allocate_sweep <- function(state, object, roots, line) {
    address <- first_fit(free_list(state), object$size)
    if (is.null(address)) {
        if (state$kind == "REFCOUNT") collect_backup(state, roots, line, object$size) else collect_sweep(
            state,
            roots,
            line,
            object$size
        )
        address <- first_fit(free_list(state), object$size)
        if (is.null(address)) return(FALSE)
    }
    object$address <- address
    state$objects <- c(state$objects, list(object))
    TRUE
}
allocate_compact <- function(state, object, roots, line) {
    if (state$top + object$size > state$size) {
        record <- collection_record(
            length(state$records) + 1L,
            line,
            object$size,
            "compact",
            free_list(state)
        )
        mark(record, roots, state$objects, state$placed)
        record$work <- record$work + length(state$objects) + length(roots)
        destination <- 0L
        survivors <- list()
        for (current in by_address(state$objects)) {
            if (!current$marked) {
                add_object(record, "freed", current)
                next
            }
            record$work <- record$work + length(current$fields)
            if (current$address != destination) {
                add_object(record, "moved", current)
                record$work <- record$work + current$size
                current$address <- destination
                current$moves <- current$moves + 1L
            }
            destination <- destination + current$size
            survivors <- c(survivors, list(current))
        }
        state$objects <- survivors
        state$top <- destination
        finish_record(state, record)
    }
    if (state$top + object$size > state$size) return(FALSE)
    object$address <- state$top
    state$top <- state$top + object$size
    state$objects <- c(state$objects, list(object))
    TRUE
}
