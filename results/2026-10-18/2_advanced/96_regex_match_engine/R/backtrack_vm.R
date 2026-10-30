new_backtrack <- function(pattern, text, full) {
    record(engine = "backtrack", program = pattern$program, flags = pattern$flags,
        groups = pattern$groups, text = text, full = full, steps = 0L)
}
execute_backtrack <- function(vm, initial_instruction, initial_position, initial_captures, partial) {
    stack <- list(list(pc = initial_instruction, position = initial_position, captures = initial_captures, visited = rep(FALSE, length(vm$program))))
    while (length(stack)) {
        state <- stack[[length(stack)]]
        stack[[length(stack)]] <- NULL
        pc <- state$pc
        position <- state$position
        captures <- state$captures
        visited <- state$visited
        repeat {
            vm$steps <- vm$steps + 1L
            if (vm$steps > 200000L) stop(structure(list(message = "TOO_MANY_STEPS"), class = c("too_many_steps", "error", "condition")))
            instruction <- vm$program[[pc + 1L]]
            op <- instruction$op
            if (op %in% c("CHAR", "ANY", "CLASS")) {
                accepts <- if (op == "CHAR") {
                    test_char(vm$text, position, instruction$character, vm$flags)
                } else if (op == "ANY") {
                    test_any(vm$text, position, vm$flags)
                } else test_class(vm$text, position, instruction$codes, instruction$negated, vm$flags)
                if (!accepts) break
                position <- position + 1L
                pc <- pc + 1L
                visited <- rep(FALSE, length(vm$program))
            } else if (op == "SPLIT") {
                if (visited[pc + 1L]) break
                visited[pc + 1L] <- TRUE
                stack[[length(stack) + 1L]] <- list(pc = instruction$y, position = position, captures = captures, visited = visited)
                pc <- instruction$x
            } else if (op == "JMP") {
                pc <- instruction$x
            } else if (op == "SAVE") {
                captures[instruction$slot + 1L] <- position
                pc <- pc + 1L
            } else if (op == "ASSERT") {
                if (!assertion(instruction$kind, vm$text, position, vm$flags)) break
                pc <- pc + 1L
            } else if (op == "BACKREF") {
                beginning <- captures[2L * instruction$group + 1L]
                finish <- captures[2L * instruction$group + 2L]
                if (beginning < 0L || finish < 0L || beginning > finish) break
                distance <- finish - beginning
                if (position + distance > nchar(vm$text)) break
                accepts <- TRUE
                for (offset in seq_len(distance) - 1L) {
                    if (!characters_equal(substr(vm$text, position + offset + 1L, position + offset + 1L),
                        substr(vm$text, beginning + offset + 1L, beginning + offset + 1L), vm$flags)) {
                        accepts <- FALSE
                        break
                    }
                }
                if (!accepts) break
                position <- position + distance
                pc <- pc + 1L
                if (distance > 0L) visited <- rep(FALSE, length(vm$program))
            } else if (op == "LOOK") {
                result <- execute_backtrack(vm, pc + 1L, position, captures, TRUE)
                if (instruction$kind == "NOT") {
                    if (!is.null(result)) break
                } else {
                    if (is.null(result)) break
                    captures <- result$captures
                    if (instruction$kind == "ATOMIC") {
                        if (result$position > position) visited <- rep(FALSE, length(vm$program))
                        position <- result$position
                    }
                }
                pc <- instruction$x
            } else if (partial || !vm$full || position == nchar(vm$text)) {
                return(list(captures = captures, position = position))
            } else break
        }
    }
    NULL
}
search_backtrack <- function(vm, start) {
    positions <- if (vm$full) 0L else seq.int(start, nchar(vm$text))
    for (beginning in positions) {
        found <- execute_backtrack(vm, 0L, beginning, rep.int(-1L, 2L * (vm$groups + 1L)), FALSE)
        if (!is.null(found)) return(found$captures)
    }
    NULL
}
