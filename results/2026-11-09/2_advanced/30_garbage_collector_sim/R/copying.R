allocate_copying <- function(state, object, roots, line) {
    half <- state$size %/% 2L
    if (state$top + object$size > state$base + half) {
        record <- collection_record(length(state$records) + 1L, line, object$size, "copy", free_list(state))
        state$base <- half - state$base
        state$top <- state$base
        copied <- integer()
        queue <- list()
        copy_object <- function(id) {
            if (id == 0L || id %in% copied) return(invisible(NULL))
            copied <<- c(copied, id)
            current <- state$placed[[id]]
            current$address <- state$top
            state$top <- state$top + current$size
            current$moves <- current$moves + 1L
            add_object(record, "live", current)
            add_object(record, "moved", current)
            queue <<- c(queue, list(current))
        }
        record$work <- record$work + length(roots)
        for (root in roots) copy_object(root)
        index <- 1L
        while (index <= length(queue)) {
            current <- queue[[index]]
            index <- index + 1L
            record$work <- record$work + current$size + length(current$fields)
            for (id in current$fields) copy_object(id)
        }
        for (current in state$objects) if (!(current$number %in% copied)) add_object(record, "freed", current)
        state$objects <- queue
        finish_record(state, record)
    }
    if (state$top + object$size > state$base + half) return(FALSE)
    object$address <- state$top
    state$top <- state$top + object$size
    state$objects <- c(state$objects, list(object))
    TRUE
}
