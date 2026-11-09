write_barrier <- function(state, target, value) {
    if (is_young(state, target)) return(invisible(NULL))
    state$barriers <- state$barriers + 1L
    if (value != 0L && is_young(state, state$placed[[value]]) && !(target$number %in% state$remembered)) {
        state$remembered <- c(state$remembered, target$number)
        state$remembers <- state$remembers + 1L
    }
}
collect_generational <- function(state, kind, roots, line, request) {
    record <- collection_record(length(state$records) + 1L, line, request, kind, free_list(state))
    marking <- kind %in% c("major", "full")
    tenuring <- kind %in% c("tenure", "full")
    if (marking) {
        mark(record, roots, state$objects, state$placed)
        survivors <- list()
        for (object in state$objects) {
            if (is_young(state, object)) survivors <- c(survivors, list(object)) else {
                record$work <- record$work + 1L
                if (object$marked) survivors <- c(survivors, list(object)) else {
                    add_object(record, "freed", object)
                    state$remembered <- setdiff(state$remembered, object$number)
                }
            }
        }
        state$objects <- survivors
    }
    pending <- vapply(
        Filter(function(object) is_young(state, object), state$objects),
        function(object) object$number,
        0L
    )
    destination <- state$young %/% 2L - state$base
    target <- destination
    queue <- list()
    evacuate <- function(id) {
        if (id == 0L || !(id %in% pending)) return(TRUE)
        pending <<- setdiff(pending, id)
        object <- state$placed[[id]]
        object$age <- object$age + 1L
        object$moves <- object$moves + 1L
        if (tenuring || object$age >= state$promotion_age) {
            address <- first_fit(old_blocks(state), object$size)
            if (is.null(address)) return(FALSE)
            object$address <- address
            add_object(record, "promoted", object)
        } else {
            object$address <- target
            target <<- target + object$size
        }
        add_object(record, "moved", object)
        if (!marking) add_object(record, "live", object)
        queue <<- c(queue, list(object))
        TRUE
    }
    record$work <- record$work + length(roots)
    for (root in roots) if (!evacuate(root)) return(FALSE)
    for (object in by_address(state$placed[state$remembered])) {
        record$work <- record$work + 1L + length(object$fields)
        for (id in object$fields) if (!evacuate(id)) return(FALSE)
    }
    index <- 1L
    while (index <= length(queue)) {
        object <- queue[[index]]
        index <- index + 1L
        record$work <- record$work + object$size + length(object$fields)
        for (id in object$fields) if (!evacuate(id)) return(FALSE)
    }
    for (object in state$objects) if (object$number %in% pending) add_object(record, "freed", object)
    state$objects <- Filter(function(object) !(object$number %in% pending), state$objects)
    state$base <- destination
    state$top <- target
    remembered <- Filter(
        function(object) !is_young(state, object) && any(vapply(
            object$fields,
            function(id) id != 0L && is_young(state, state$placed[[id]]),
            FALSE
        )),
        state$objects
    )
    state$remembered <- vapply(remembered, function(object) object$number, 0L)
    finish_record(state, record)
    TRUE
}
allocate_generational <- function(state, object, roots, line) {
    fits <- function() state$top + object$size <= state$base + state$young %/% 2L
    for (step in seq.int(0L, 2L)) {
        if (fits()) {
            object$address <- state$top
            state$top <- state$top + object$size
            state$objects <- c(state$objects, list(object))
            return(TRUE)
        }
        if (step == 2L) break
        kind <- if (largest_free(old_blocks(state)) < state$top - state$base) {
            if (step == 0L) "major" else "full"
        } else if (step == 0L) "minor" else "tenure"
        if (!collect_generational(state, kind, roots, line, object$size)) return(FALSE)
    }
    FALSE
}
