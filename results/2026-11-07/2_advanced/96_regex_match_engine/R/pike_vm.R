new_pike <- function(pattern, text, full) {
    record(engine = "pike", program = pattern$program, flags = pattern$flags,
        groups = pattern$groups, text = text, full = full, steps = 0L)
}
new_thread_list <- function(vm) record(threads = list(), marks = rep(FALSE, length(vm$program)))
add_thread <- function(vm, thread_list, pc, captures, position) {
    pending <- list(list(pc = pc, captures = captures))
    while (length(pending)) {
        thread <- pending[[length(pending)]]
        pending[[length(pending)]] <- NULL
        pc <- thread$pc
        captures <- thread$captures
        if (thread_list$marks[pc + 1L]) next
        thread_list$marks[pc + 1L] <- TRUE
        vm$steps <- vm$steps + 1L
        entry <- vm$program[[pc + 1L]]
        if (entry$op == "JMP") {
            pending[[length(pending) + 1L]] <- list(pc = entry$x, captures = captures)
        } else if (entry$op == "SPLIT") {
            pending[[length(pending) + 1L]] <- list(pc = entry$y, captures = captures)
            pending[[length(pending) + 1L]] <- list(pc = entry$x, captures = captures)
        } else if (entry$op == "SAVE") {
            updated <- captures
            updated[entry$slot + 1L] <- position
            pending[[length(pending) + 1L]] <- list(pc = pc + 1L, captures = updated)
        } else if (entry$op == "ASSERT") {
            if (assertion(entry$kind, vm$text, position, vm$flags)) pending[[length(pending) + 1L]] <- list(pc = pc + 1L, captures = captures)
        } else thread_list$threads[[length(thread_list$threads) + 1L]] <- list(pc = pc, captures = captures)
    }
}
search_pike <- function(vm, start) {
    current <- new_thread_list(vm)
    position <- start
    matched <- NULL
    repeat {
        if (is.null(matched) && (!vm$full || position == start)) add_thread(vm, current, 0L, rep.int(-1L, 2L * (vm$groups + 1L)), position)
        following <- new_thread_list(vm)
        for (thread in current$threads) {
            vm$steps <- vm$steps + 1L
            entry <- vm$program[[thread$pc + 1L]]
            if (entry$op == "MATCH") {
                if (!vm$full || position == nchar(vm$text)) {
                    matched <- thread$captures
                    break
                }
                next
            }
            accepts <- if (entry$op == "CHAR") {
                test_char(vm$text, position, entry$character, vm$flags)
            } else if (entry$op == "ANY") {
                test_any(vm$text, position, vm$flags)
            } else test_class(vm$text, position, entry$codes, entry$negated, vm$flags)
            if (accepts) add_thread(vm, following, thread$pc + 1L, thread$captures, position + 1L)
        }
        if (position == nchar(vm$text)) return(matched)
        if (!length(following$threads) && (!is.null(matched) || vm$full)) return(matched)
        current <- following
        position <- position + 1L
    }
}
