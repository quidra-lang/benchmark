options(scipen = 999)
emit <- function(...) cat(paste0(...), "\n", sep = "")
evaluation_error <- function() stop(structure(list(message = "division by zero", call = NULL), class = c("evaluation_error", "error", "condition")))

expression <- function(text) {
    if (is.null(text)) return(NULL)
    tokens <- regmatches(text, gregexpr("\\|\\||&&|==|!=|<=|>=|[()+*/%!<>-]|[0-9]+|[A-Za-z_][A-Za-z0-9_]*", text, perl = TRUE))[[1]]
    index <- 1L
    references <- list()
    precedence <- list("||" = 0L, "&&" = 1L, "==" = 2L, "!=" = 2L, "<" = 2L, "<=" = 2L, ">" = 2L, ">=" = 2L, "+" = 3L, "-" = 3L, "*" = 4L, "/" = 4L, "%" = 4L)
    parse <- function(level) {
        if (level == 5L) return(unary())
        left <- parse(level + 1L)
        repeat {
            token <- if (index <= length(tokens)) tokens[index] else ""
            priority <- precedence[[token]]
            if (is.null(priority) || priority != level) break
            index <<- index + 1L
            right <- parse(level + 1L)
            left <- list(operator = token, left = left, right = right)
        }
        left
    }
    unary <- function() {
        token <- tokens[index]
        index <<- index + 1L
        if (token %in% c("!", "-")) return(list(operator = if (token == "!") "not" else "negative", left = unary()))
        if (token == "(") {
            result <- parse(0L)
            index <<- index + 1L
            return(result)
        }
        if (token == "in") {
            index <<- index + 1L
            state <- tokens[index]
            index <<- index + 2L
            references[[length(references) + 1L]] <<- list(kind = "state", name = state)
            return(list(operator = "in", left = state))
        }
        if (grepl("\\A[0-9]+\\z", token, perl = TRUE)) return(list(operator = "number", left = as.numeric(token)))
        if (token != "_data") references[[length(references) + 1L]] <<- list(kind = "variable", name = token)
        list(operator = "variable", left = token)
    }
    tree <- parse(0L)
    list(tree = tree, references = references)
}
evaluate_expression <- function(expression, variables, data, configuration) {
    evaluate <- function(node) {
        operator <- node$operator
        if (operator == "number") return(node$left)
        if (operator == "variable") return(if (node$left == "_data") data else variables[[node$left]])
        if (operator == "in") return(as.numeric(!is.null(configuration[[node$left]])))
        if (operator %in% c("not", "negative")) {
            value <- evaluate(node$left)
            return(if (operator == "not") as.numeric(value == 0) else -value)
        }
        a <- evaluate(node$left)
        if (operator == "&&" && a == 0) return(0)
        if (operator == "||" && a != 0) return(1)
        b <- evaluate(node$right)
        if (operator %in% c("/", "%") && b == 0) evaluation_error()
        switch(operator,
            "+" = a + b, "-" = a - b, "*" = a * b, "/" = trunc(a / b), "%" = a - trunc(a / b) * b,
            "==" = as.numeric(a == b), "!=" = as.numeric(a != b), "<" = as.numeric(a < b),
            "<=" = as.numeric(a <= b), ">" = as.numeric(a > b), ">=" = as.numeric(a >= b),
            "&&" = as.numeric(b != 0), "||" = as.numeric(b != 0))
    }
    evaluate(expression$tree)
}
new_state <- function(name, kind, parent = NULL) {
    state <- new.env(parent = emptyenv())
    state$name <- name
    state$kind <- kind
    state$parent <- parent
    state$children <- list()
    state$initial <- state$history_kind <- state$default <- NULL
    state$entries <- state$exits <- state$transitions <- list()
    state$depth <- if (is.null(parent)) 0 else parent$depth + 1
    state$entered <- state$taken <- state$dwell <- state$entry_time <- 0
    state
}
child_states <- function(state) Filter(function(child) child$kind != "history", state$children)
compound <- function(state) state$kind == "root" || (state$kind == "state" && length(child_states(state)) > 0)
parallel <- function(state) state$kind == "parallel" && length(child_states(state)) > 0
atomic <- function(state) state$kind != "history" && length(child_states(state)) == 0
initial_child <- function(state) if (is.null(state$initial)) child_states(state)[[1]] else state$initial
descendant <- function(state, ancestor) {
    parent <- state$parent
    while (!is.null(parent)) {
        if (identical(parent, ancestor)) return(TRUE)
        parent <- parent$parent
    }
    FALSE
}
merge_set <- function(a, b) {
    for (name in names(b)) a[[name]] <- b[[name]]
    a
}
states_text <- function(states) if (length(states) == 0) "-" else paste(vapply(states, function(s) s$name, character(1)), collapse = ",")

make_chart <- function(definitions) {
    chart <- new.env(parent = emptyenv())
    chart$root <- new_state("", "root")
    chart$states <- chart$variables <- chart$errors <- chart$document <- list()
    chart$configuration <- chart$history <- chart$queue <- chart$reservations <- list()
    chart$creation <- chart$time <- chart$data <- chart$macrosteps <- chart$microsteps <- 0
    chart$trace <- chart$halted <- FALSE
    check_references <- function(references) {
        for (reference in references) {
            if (reference$kind == "variable" && is.null(chart$variables[[reference$name]])) return(paste0("unknown variable ", reference$name))
            if (reference$kind == "state" && is.null(chart$states[[reference$name]])) return(paste0("unknown state ", reference$name))
        }
        NULL
    }
    actions <- function(text) {
        references <- result <- list()
        parts <- if (is.null(text)) character() else strsplit(text, "; ", fixed = TRUE)[[1]]
        for (action in parts) {
            space <- regexpr(" ", action, fixed = TRUE)[1]
            kind <- substr(action, 1, space - 1L)
            rest <- substring(action, space + 1L)
            record <- list(kind = kind)
            if (kind == "raise") {
                space <- regexpr(" ", rest, fixed = TRUE)[1]
                record$event <- if (space < 0) rest else substr(rest, 1, space - 1L)
                record$expression <- expression(if (space < 0) NULL else substring(rest, space + 1L))
            } else if (kind == "send") {
                words <- strsplit(rest, " ", fixed = TRUE)[[1]]
                record$event <- words[1]
                record$delay <- as.numeric(words[2])
                record$expression <- expression(if (length(words) <= 2) NULL else paste(words[-c(1, 2)], collapse = " "))
            } else if (kind == "cancel") {
                record$event <- rest
            } else if (kind == "log") {
                if (startsWith(rest, "\"")) {
                    finish <- regexpr("\"", substring(rest, 2), fixed = TRUE)[1] + 1L
                    record$text <- substr(rest, 2, finish - 1L)
                    if (finish < nchar(rest)) record$expression <- expression(substring(rest, finish + 2L))
                } else {
                    record$expression <- expression(rest)
                }
            } else {
                equals <- regexpr(" = ", action, fixed = TRUE)[1]
                name <- substr(action, 1, equals - 1L)
                record <- list(kind = "assign", name = name, expression = expression(substring(action, equals + 3L)))
                references[[length(references) + 1L]] <- list(kind = "variable", name = name)
            }
            if (!is.null(record$expression)) references <- c(references, record$expression$references)
            result[[length(result) + 1L]] <- record
        }
        list(actions = result, references = references)
    }
    validate <- function() {
        for (definition in definitions) {
            line <- definition$text
            number <- as.character(definition$number)
            parts <- strsplit(line, " ", fixed = TRUE)[[1]]
            kind <- parts[1]
            name <- parts[2]
            if (kind %in% c("state", "parallel", "final", "history")) {
                parent_name <- if (length(parts) < 3 || (kind == "state" && parts[3] == "initial")) NULL else parts[3]
                parent <- if (is.null(parent_name)) chart$root else chart$states[[parent_name]]
                if (!is.null(chart$states[[name]])) {
                    chart$errors[[number]] <- paste0("duplicate state ", name)
                } else if (is.null(parent)) {
                    chart$errors[[number]] <- paste0("unknown state ", parent_name)
                } else if (parent$kind %in% c("final", "history")) {
                    chart$errors[[number]] <- paste0(parent_name, " cannot have children")
                } else {
                    state <- new_state(name, kind, parent)
                    if (kind == "history") {
                        state$history_kind <- parts[4]
                        state$default <- if (length(parts) >= 5) parts[5] else NULL
                    }
                    at <- match("initial", parts)
                    if (kind == "state" && !is.na(at)) state$initial <- parts[at + 1L]
                    chart$states[[name]] <- state
                    parent$children[[length(parent$children) + 1L]] <- state
                }
            } else if (kind == "var") {
                if (!is.null(chart$variables[[name]])) {
                    chart$errors[[number]] <- paste0("duplicate variable ", name)
                } else {
                    chart$variables[[name]] <- as.numeric(parts[3])
                }
            }
        }
        visit <- function(state) {
            chart$document[[length(chart$document) + 1L]] <- state
            for (child in state$children) visit(child)
        }
        for (state in chart$root$children) visit(state)
        for (definition in definitions) {
            line <- definition$text
            number <- as.character(definition$number)
            if (!is.null(chart$errors[[number]])) next
            parts <- strsplit(line, " ", fixed = TRUE)[[1]]
            kind <- parts[1]
            name <- parts[2]
            state <- chart$states[[name]]
            reason <- NULL
            if (kind == "state" && !is.null(state$initial)) {
                child <- chart$states[[state$initial]]
                if (is.null(child)) {
                    reason <- paste0("unknown state ", state$initial)
                } else if (!identical(child$parent, state) || child$kind == "history") {
                    reason <- paste0(child$name, " is not a child of ", name)
                }
            } else if (kind %in% c("final", "history")) {
                parent <- state$parent
                if (parent$kind != "state" || length(child_states(parent)) == 0) {
                    reason <- paste0(name, " needs a compound parent")
                } else if (kind == "history" && !is.null(state$default)) {
                    target <- chart$states[[state$default]]
                    if (is.null(target)) {
                        reason <- paste0("unknown state ", state$default)
                    } else if (!descendant(target, parent) || target$kind == "history") {
                        reason <- paste0(target$name, " is not a descendant of ", parent$name)
                    }
                }
            } else if (kind %in% c("entry", "exit")) {
                if (is.null(state)) {
                    reason <- paste0("unknown state ", name)
                } else if (state$kind == "history") {
                    reason <- paste0(name, " cannot have actions")
                } else {
                    slash <- regexpr(" / ", line, fixed = TRUE)[1]
                    parsed <- actions(substring(line, slash + 3L))
                    reason <- check_references(parsed$references)
                    if (is.null(reason)) {
                        if (kind == "entry") state$entries[[length(state$entries) + 1L]] <- parsed$actions else state$exits[[length(state$exits) + 1L]] <- parsed$actions
                    }
                }
            } else if (kind == "on") {
                if (is.null(state)) {
                    reason <- paste0("unknown state ", name)
                } else if (state$kind %in% c("final", "history")) {
                    reason <- paste0(name, " cannot have transitions")
                } else {
                    pattern <- "\\Aon ([^ ]+) (always|after [0-9]+|[^ ]+)(?: \\[(.*?)\\])?(?: (->|~>) ([^ ]+))?(?: / (.*))?\\z"
                    match <- regmatches(line, regexec(pattern, line, perl = TRUE))[[1]]
                    trigger <- match[3]
                    guard_text <- if (length(match) >= 4 && nzchar(match[4])) match[4] else NULL
                    arrow <- if (length(match) >= 5 && nzchar(match[5])) match[5] else NULL
                    target_name <- if (length(match) >= 6 && nzchar(match[6])) match[6] else NULL
                    action_text <- if (length(match) >= 7 && nzchar(match[7])) match[7] else NULL
                    guard <- expression(guard_text)
                    parsed <- actions(action_text)
                    references <- if (is.null(guard)) list() else guard$references
                    if (!is.null(target_name)) references[[length(references) + 1L]] <- list(kind = "state", name = target_name)
                    reason <- check_references(c(references, parsed$references))
                    if (is.null(reason)) {
                        transition <- new.env(parent = emptyenv())
                        transition$source <- state
                        transition$kind <- if (trigger == "always") "always" else if (startsWith(trigger, "after ")) "timer" else "event"
                        transition$descriptors <- if (transition$kind == "event") strsplit(trigger, "|", fixed = TRUE)[[1]] else character()
                        transition$delay <- if (transition$kind == "timer") as.numeric(strsplit(trigger, " ", fixed = TRUE)[[1]][2]) else 0
                        transition$guard <- guard
                        transition$target <- if (is.null(target_name)) NULL else chart$states[[target_name]]
                        transition$mode <- if (is.null(arrow)) "internal" else if (arrow == "~>") "local" else "external"
                        transition$actions <- parsed$actions
                        state$transitions[[length(state$transitions) + 1L]] <- transition
                    }
                }
            }
            if (!is.null(reason)) chart$errors[[number]] <- reason
        }
        if (length(chart$errors) > 0) {
            for (number in sort(as.integer(names(chart$errors)))) emit("error line ", number, ": ", chart$errors[[as.character(number)]])
            return(FALSE)
        }
        for (state in chart$document) {
            if (!is.null(state$initial)) state$initial <- chart$states[[state$initial]]
            if (!is.null(state$default)) state$default <- chart$states[[state$default]]
        }
        TRUE
    }
    default_target <- function(history) if (is.null(history$default)) initial_child(history$parent) else history$default
    warn_unreachable <- function() {
        initial <- initial_child(chart$root)
        reachable <- setNames(list(initial), initial$name)
        repeat {
            before <- length(reachable)
            for (state in reachable) {
                if (!identical(state$parent, chart$root)) reachable[[state$parent$name]] <- state$parent
                if (compound(state)) {
                    child <- initial_child(state)
                    reachable[[child$name]] <- child
                }
                if (parallel(state)) for (child in child_states(state)) reachable[[child$name]] <- child
                for (transition in state$transitions) {
                    target <- transition$target
                    if (!is.null(target)) {
                        if (target$kind == "history") target <- default_target(target)
                        reachable[[target$name]] <- target
                    }
                }
            }
            if (length(reachable) == before) break
        }
        for (state in chart$document) if (state$kind != "history" && is.null(reachable[[state$name]])) emit("warning: unreachable state ", state$name)
    }
    evaluate <- function(value) evaluate_expression(value, chart$variables, chart$data, chart$configuration)
    reserve <- function(record) {
        chart$creation <- chart$creation + 1
        record$due <- chart$time + record$delay
        record$number <- chart$creation
        chart$reservations[[length(chart$reservations) + 1L]] <- record
    }
    run_actions <- function(list) {
        tryCatch({
            for (action in list) {
                value <- if (is.null(action$expression)) 0 else evaluate(action$expression)
                if (action$kind == "assign") chart$variables[[action$name]] <- value
                if (action$kind == "raise") chart$queue[[length(chart$queue) + 1L]] <- list(event = action$event, value = value)
                if (action$kind == "send") reserve(list(kind = "send", event = action$event, value = value, delay = action$delay))
                if (action$kind == "cancel") chart$reservations <- Filter(function(r) r$kind != "send" || r$event != action$event, chart$reservations)
                if (action$kind == "log") emit(if (is.null(action$expression)) action$text else paste0(if (is.null(action$text)) "" else action$text, value))
            }
        }, evaluation_error = function(error) {
            chart$queue[[length(chart$queue) + 1L]] <- list(event = "error.execution", value = 0)
        })
    }
    effective_targets <- function(transition) {
        target <- transition$target
        if (is.null(target)) return(list())
        if (target$kind != "history") return(list(target))
        if (is.null(chart$history[[target$name]])) list(default_target(target)) else chart$history[[target$name]]
    }
    choice <- function(transition) {
        if (transition$mode == "internal") return(list(transition = transition, scope = NULL, exits = list()))
        targets <- effective_targets(transition)
        all_descendants <- function(ancestor) all(vapply(targets, function(target) descendant(target, ancestor), logical(1)))
        source <- transition$source
        if (transition$mode == "local" && compound(source) && all_descendants(source)) {
            scope <- source
        } else {
            scope <- source$parent
            while (!compound(scope) || !all_descendants(scope)) scope <- scope$parent
        }
        list(transition = transition, scope = scope, exits = Filter(function(state) descendant(state, scope), chart$configuration))
    }
    matches <- function(transition, trigger) {
        if (trigger$kind == "always") return(transition$kind == "always")
        if (trigger$kind == "timer") return(identical(transition, trigger$transition))
        if (transition$kind != "event") return(FALSE)
        any(vapply(transition$descriptors, function(descriptor) descriptor == "*" || descriptor == trigger$event || startsWith(trigger$event, paste0(descriptor, ".")), logical(1)))
    }
    select_transitions <- function(trigger) {
        selected <- list()
        for (active in chart$document) {
            if (is.null(chart$configuration[[active$name]]) || !atomic(active)) next
            state <- active
            found <- NULL
            while (!identical(state, chart$root) && is.null(found)) {
                for (transition in state$transitions) {
                    if (!matches(transition, trigger)) next
                    accepted <- tryCatch(is.null(transition$guard) || evaluate(transition$guard) != 0, evaluation_error = function(error) {
                        chart$queue[[length(chart$queue) + 1L]] <- list(event = "error.execution", value = 0)
                        FALSE
                    })
                    if (accepted) {
                        found <- transition
                        break
                    }
                }
                state <- state$parent
            }
            if (!is.null(found) && !any(vapply(selected, function(t) identical(t, found), logical(1)))) selected[[length(selected) + 1L]] <- found
        }
        occupied <- result <- list()
        for (transition in selected) {
            candidate <- choice(transition)
            if (any(names(candidate$exits) %in% names(occupied))) next
            occupied <- merge_set(occupied, candidate$exits)
            result[[length(result) + 1L]] <- candidate
        }
        result
    }
    expand_entry <- function(set) {
        repeat {
            before <- length(set)
            for (state in set) {
                if (parallel(state)) {
                    for (child in child_states(state)) set[[child$name]] <- child
                } else if (compound(state) && !any(vapply(child_states(state), function(child) !is.null(set[[child$name]]), logical(1)))) {
                    child <- initial_child(state)
                    set[[child$name]] <- child
                }
            }
            if (length(set) == before) break
        }
        set
    }
    complete <- function(state) {
        if (compound(state)) return(any(vapply(child_states(state), function(child) child$kind == "final" && !is.null(chart$configuration[[child$name]]), logical(1))))
        if (parallel(state)) return(all(vapply(child_states(state), complete, logical(1))))
        FALSE
    }
    enter <- function(set) {
        for (state in chart$document) {
            if (is.null(set[[state$name]])) next
            chart$configuration[[state$name]] <- state
            state$entered <- state$entered + 1
            state$entry_time <- chart$time
            for (transition in state$transitions) if (transition$kind == "timer") reserve(list(kind = "timer", transition = transition, delay = transition$delay))
            for (list in state$entries) run_actions(list)
            if (state$kind == "final") {
                parent <- state$parent
                chart$queue[[length(chart$queue) + 1L]] <- list(event = paste0("done.state.", parent$name), value = 0)
                grandparent <- parent$parent
                if (parallel(grandparent) && all(vapply(child_states(grandparent), complete, logical(1)))) chart$queue[[length(chart$queue) + 1L]] <- list(event = paste0("done.state.", grandparent$name), value = 0)
            }
        }
    }
    trigger_name <- function(trigger) {
        if (trigger$kind == "always") return("always")
        if (trigger$kind == "timer") return(paste0("after(", trigger$transition$delay, ")@", trigger$transition$source$name))
        paste0(trigger$event, if (trigger$value == 0) "" else paste0("=", trigger$value))
    }
    microstep <- function(selected, trigger) {
        exits <- list()
        for (candidate in selected) exits <- merge_set(exits, candidate$exits)
        for (state in chart$document) {
            if (state$kind != "history" || is.null(exits[[state$parent$name]])) next
            chart$history[[state$name]] <- Filter(function(active) {
                !is.null(chart$configuration[[active$name]]) && if (state$history_kind == "deep") atomic(active) && descendant(active, state$parent) else identical(active$parent, state$parent)
            }, chart$document)
        }
        entries <- list()
        for (candidate in selected) {
            transition <- candidate$transition
            if (transition$mode == "internal") next
            for (target in effective_targets(transition)) {
                state <- target
                while (descendant(state, candidate$scope)) {
                    entries[[state$name]] <- state
                    state <- state$parent
                }
            }
        }
        entries <- expand_entry(entries)
        if (chart$trace) {
            sources <- lapply(selected, function(candidate) candidate$transition$source)
            exit_list <- Filter(function(state) !is.null(exits[[state$name]]), rev(chart$document))
            entry_list <- Filter(function(state) !is.null(entries[[state$name]]), chart$document)
            emit("[t=", chart$time, "] ", trigger_name(trigger), " (", states_text(sources), "): exit ", states_text(exit_list), "; enter ", states_text(entry_list))
        }
        for (state in rev(chart$document)) {
            if (is.null(exits[[state$name]])) next
            for (list in state$exits) run_actions(list)
            chart$configuration[[state$name]] <- NULL
            state$dwell <- state$dwell + chart$time - state$entry_time
            chart$reservations <- Filter(function(r) r$kind != "timer" || !identical(r$transition$source, state), chart$reservations)
        }
        for (candidate in selected) {
            transition <- candidate$transition
            run_actions(transition$actions)
            transition$source$taken <- transition$source$taken + 1
        }
        enter(entries)
    }
    macrostep <- function(trigger) {
        chart$macrosteps <- chart$macrosteps + 1
        count <- 0L
        perform <- function(selected, current) {
            if (count == 1000L) {
                emit("LIVELOCK t=", chart$time)
                chart$halted <- TRUE
            } else {
                count <<- count + 1L
                chart$microsteps <- chart$microsteps + 1
                microstep(selected, current)
            }
        }
        chart$data <- if (trigger$kind == "event") trigger$value else 0
        if (trigger$kind == "start") {
            initial <- initial_child(chart$root)
            enter(expand_entry(setNames(list(initial), initial$name)))
        } else {
            selected <- select_transitions(trigger)
            if (length(selected) > 0) perform(selected, trigger)
        }
        while (!chart$halted) {
            chart$data <- 0
            current <- list(kind = "always")
            selected <- select_transitions(current)
            if (length(selected) > 0) {
                perform(selected, current)
                next
            }
            if (length(chart$queue) == 0) break
            event <- chart$queue[[1]]
            chart$queue <- chart$queue[-1]
            chart$data <- event$value
            current <- list(kind = "event", event = event$event, value = event$value)
            selected <- select_transitions(current)
            if (length(selected) > 0) perform(selected, current)
        }
    }
    ordered_reservations <- function() {
        reservations <- chart$reservations
        if (length(reservations) > 0) reservations <- reservations[order(vapply(reservations, function(r) r$due, numeric(1)), vapply(reservations, function(r) r$number, numeric(1)))]
        reservations
    }
    dump <- function() {
        emit("dump t=", chart$time)
        for (state in chart$document) if (!is.null(chart$configuration[[state$name]])) emit(paste(rep("  ", state$depth), collapse = ""), state$name)
        for (name in sort(names(chart$variables), method = "radix")) emit("  var ", name, " = ", chart$variables[[name]])
        for (state in chart$document) if (!is.null(chart$history[[state$name]])) emit("  history ", state$name, " = ", states_text(chart$history[[state$name]]))
        for (reservation in ordered_reservations()) {
            if (reservation$kind == "timer") emit("  timer ", reservation$due, " ", trigger_name(reservation)) else emit("  send ", reservation$due, " ", reservation$event, " ", reservation$value)
        }
    }
    run <- function(script) {
        if (!validate()) return(invisible(NULL))
        warn_unreachable()
        macrostep(list(kind = "start"))
        for (line in script) {
            if (chart$halted) break
            space <- regexpr(" ", line, fixed = TRUE)[1]
            command <- if (space < 0) line else substr(line, 1, space - 1L)
            rest <- if (space < 0) "" else substring(line, space + 1L)
            if (command == "event") {
                parts <- strsplit(rest, " ", fixed = TRUE)[[1]]
                macrostep(list(kind = "event", event = parts[1], value = if (length(parts) >= 2) as.numeric(parts[2]) else 0))
            } else if (command == "tick") {
                finish <- chart$time + as.numeric(rest)
                while (!chart$halted) {
                    reservations <- ordered_reservations()
                    if (length(reservations) == 0 || reservations[[1]]$due > finish) break
                    next_reservation <- reservations[[1]]
                    chart$reservations <- Filter(function(r) r$number != next_reservation$number, chart$reservations)
                    chart$time <- next_reservation$due
                    trigger <- if (next_reservation$kind == "timer") next_reservation else list(kind = "event", event = next_reservation$event, value = next_reservation$value)
                    macrostep(trigger)
                }
                if (!chart$halted) chart$time <- finish
            } else if (command == "set") {
                parts <- strsplit(rest, " ", fixed = TRUE)[[1]]
                name <- parts[1]
                if (!is.null(chart$variables[[name]])) chart$variables[[name]] <- as.numeric(parts[2]) else emit("error: unknown variable ", name)
            } else if (command == "trace") {
                chart$trace <- rest == "on"
            } else if (command == "eval") {
                value <- expression(rest)
                reason <- check_references(value$references)
                if (!is.null(reason)) {
                    emit("error: ", reason)
                } else {
                    chart$data <- 0
                    tryCatch({
                        result <- evaluate(value)
                        emit(rest, " -> ", result)
                    }, evaluation_error = function(error) emit("error: division by zero"))
                }
            } else if (command == "dump") {
                dump()
            }
        }
        emit("end t=", chart$time, " macrosteps=", chart$macrosteps, " microsteps=", chart$microsteps)
        for (state in chart$document) {
            if (state$kind == "history") next
            time <- state$dwell + if (is.null(chart$configuration[[state$name]])) 0 else chart$time - state$entry_time
            emit("  ", state$name, " entered=", state$entered, " taken=", state$taken, " time=", time)
        }
        invisible(NULL)
    }
    run
}

input <- readLines(file("stdin"), warn = FALSE)
i <- 2L
for (chart in seq_len(as.integer(input[1]))) {
    name <- strsplit(input[i], " ", fixed = TRUE)[[1]][2]
    i <- i + 1L
    definitions <- list()
    while (input[i] != "RUN") {
        definitions[[length(definitions) + 1L]] <- list(text = input[i], number = i)
        i <- i + 1L
    }
    i <- i + 1L
    script <- character()
    while (input[i] != "END") {
        script <- c(script, input[i])
        i <- i + 1L
    }
    i <- i + 1L
    emit("chart ", name)
    make_chart(definitions)(script)
}
