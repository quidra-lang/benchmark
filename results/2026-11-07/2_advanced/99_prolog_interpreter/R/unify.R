new_trail <- function() record(bindings = new_table(), height = 0L)
trail_mark <- function(trail) trail$height
undo <- function(trail, mark) {
    while (trail$height > mark) {
        key <- as.character(trail$height)
        trail$bindings[[key]]$binding <- NULL
        rm(list = key, envir = trail$bindings)
        trail$height <- trail$height - 1L
    }
}
bind_variable <- function(trail, variable, value) {
    variable$binding <- value
    trail$height <- trail$height + 1L
    trail$bindings[[as.character(trail$height)]] <- variable
}
unify <- function(trail, left, right) {
    pending <- list(list(left, right))
    while (length(pending)) {
        pair <- pending[[length(pending)]]
        pending[[length(pending)]] <- NULL
        left <- dereference(pair[[1L]])
        right <- dereference(pair[[2L]])
        if (is_variable(left) && is_variable(right) && left$id == right$id) next
        if (is_variable(left)) bind_variable(trail, left, right) else if (is_variable(right)) bind_variable(trail, right, left) else if (is_compound(left) && is_compound(right)) {
            if (left$name != right$name || length(left$arguments) != length(right$arguments)) return(FALSE)
            for (index in rev(seq_along(left$arguments))) pending[[length(pending) + 1L]] <- list(left$arguments[[index]], right$arguments[[index]])
        } else if (is_integer(left) && is_integer(right)) {
            if (left$value != right$value) return(FALSE)
        } else if (is_atom(left) && is_atom(right)) {
            if (left$name != right$name) return(FALSE)
        } else return(FALSE)
    }
    TRUE
}
identical_terms <- function(left, right) {
    pending <- list(list(left, right))
    while (length(pending)) {
        pair <- pending[[length(pending)]]
        pending[[length(pending)]] <- NULL
        left <- dereference(pair[[1L]])
        right <- dereference(pair[[2L]])
        if (is_variable(left) && is_variable(right) && left$id == right$id) next
        if (is_variable(left) || is_variable(right)) return(FALSE)
        if (is_compound(left) && is_compound(right)) {
            if (left$name != right$name || length(left$arguments) != length(right$arguments)) return(FALSE)
            for (index in rev(seq_along(left$arguments))) pending[[length(pending) + 1L]] <- list(left$arguments[[index]], right$arguments[[index]])
        } else if (is_integer(left) && is_integer(right)) {
            if (left$value != right$value) return(FALSE)
        } else if (is_atom(left) && is_atom(right)) {
            if (left$name != right$name) return(FALSE)
        } else return(FALSE)
    }
    TRUE
}
