source("terms.R")
source("unify.R")
source("database.R")
source("reader.R")
source("predicates.R")

CONTROLS <- c(predicate_keys(c(",", ";", "->"), 2L), predicate_keys("!", 0L), predicate_keys("\\+", 1L),
    predicate_keys("catch", 3L), vapply(1L:8L, function(arity) indicator_key("call", arity), character(1L)))
BUILTIN_PREDICATES <- c(DETERMINISTIC, predicate_keys(c("findall", "between"), 3L), predicate_keys("throw", 1L), predicate_keys("length", 2L))
goal_conversion <- function(term) {
    term <- dereference(term)
    if (is_variable(term)) return(compound("call", term))
    if (is_integer(term)) return(NULL)
    if (is_compound(term) && term$name %in% c(",", ";", "->") && length(term$arguments) == 2L) {
        left <- goal_conversion(term$arguments[[1L]])
        if (is.null(left)) return(NULL)
        right <- goal_conversion(term$arguments[[2L]])
        return(if (is.null(right)) NULL else compound(term$name, left, right))
    }
    term
}
atom_name <- function(name, quoted) {
    characters <- strsplit(name, "", fixed = TRUE)[[1L]]
    plain <- name %in% c("[]", "!", ";") || (length(characters) > 0L && lowercase_letter(characters[1L]) &&
        all(vapply(characters, alphanumeric, logical(1L)))) || (length(characters) > 0L && name != "." && all(characters %in% SYMBOLS))
    if (!quoted || plain) return(name)
    escaped <- vapply(characters, function(character) {
        if (character == "\\") "\\\\" else if (character == "'") "\\'" else if (character == "\n") "\\n" else if (character == "\t") "\\t" else character
    }, character(1L))
    paste0("'", paste0(escaped, collapse = ""), "'")
}
new_writer <- function(names = NULL, quoted = TRUE) {
    names <- if (is.null(names)) new_table() else list2env(as.list(names, all.names = TRUE), parent = emptyenv())
    record(names = names, next_name = 1L, quoted = quoted)
}
write_term <- function(writer, term, limit = 1200L, operand = FALSE) {
    term <- dereference(term)
    if (is_variable(term)) {
        key <- variable_key(term)
        if (!exists(key, writer$names, inherits = FALSE)) {
            writer$names[[key]] <- paste0("_G", writer$next_name)
            writer$next_name <- writer$next_name + 1L
        }
        return(writer$names[[key]])
    }
    if (is_integer(term)) return(as.character(term$value))
    if (is_atom(term)) {
        text <- atom_name(term$name, writer$quoted)
        operator <- (term$name != "" && exists(term$name, INFIX, inherits = FALSE)) || term$name %in% names(PREFIX)
        return(if (operand && operator) paste0("(", text, ")") else text)
    }
    name <- term$name
    arguments <- term$arguments
    if (name == "." && length(arguments) == 2L) {
        parts <- list_parts(term)
        elements <- vapply(parts$elements, function(element) write_term(writer, element, 999L), character(1L))
        text <- paste0("[", paste0(elements, collapse = ","))
        if (!is_atom(parts$tail, "[]")) text <- paste0(text, "|", write_term(writer, parts$tail, 999L))
        return(paste0(text, "]"))
    }
    if (length(arguments) == 2L && name != "" && exists(name, INFIX, inherits = FALSE)) {
        limits <- INFIX[[name]]
        left <- write_term(writer, arguments[[1L]], limits[2L], TRUE)
        right <- write_term(writer, arguments[[2L]], limits[3L], TRUE)
        if (name == ",") text <- paste0(left, ",", right) else if (lowercase_letter(substr(name, 1L, 1L))) text <- paste(left, name, right) else {
            before <- if (left != "" && substr(left, nchar(left), nchar(left)) %in% SYMBOLS) " " else ""
            after <- if (right != "" && substr(right, 1L, 1L) %in% SYMBOLS) " " else ""
            text <- paste0(left, before, name, after, right)
        }
        return(if (limits[1L] > limit) paste0("(", text, ")") else text)
    }
    if (length(arguments) == 1L && name %in% names(PREFIX)) {
        priority <- PREFIX[[name]]
        argument <- write_term(writer, arguments[[1L]], priority, TRUE)
        initial <- substr(argument, 1L, 1L)
        space <- if (argument != "" && (initial %in% SYMBOLS || digit(initial) || initial == "(")) " " else ""
        text <- paste0(name, space, argument)
        return(if (priority > limit) paste0("(", text, ")") else text)
    }
    values <- vapply(arguments, function(argument) write_term(writer, argument, 999L), character(1L))
    paste0(atom_name(name, writer$quoted), "(", paste0(values, collapse = ","), ")")
}
predicate_name <- function(key) write_term(new_writer(), indicator_term(key))
new_consultant <- function() {
    last <- new_table()
    last[["prelude.pl"]] <- last[["program.pl"]] <- NULL
    record(database = new_database(), lines = character(), counts = list(prelude.pl = integer(3L), program.pl = integer(3L)),
        last = last, discontiguous = new_table())
}
warning <- function(consultant, file, line, message) {
    consultant$lines <- c(consultant$lines, paste0(file, ":", line, ": warning: ", message))
    consultant$counts[[file]][3L] <- consultant$counts[[file]][3L] + 1L
}
consult_clause <- function(consultant, term, file, line, reader) {
    head <- term
    body <- NULL
    if (is_compound(term) && indicator(term) == indicator_key(":-", 2L)) {
        head <- term$arguments[[1L]]
        body <- term$arguments[[2L]]
    }
    error <- NULL
    if (is_variable(head)) error <- atom_term("instantiation_error") else if (is_integer(head)) error <- type_error("callable", head) else if (indicator(head) %in% c(CONTROLS, BUILTIN_PREDICATES)) {
        error <- compound("permission_error", atom_term("modify"), atom_term("static_procedure"), indicator_term(indicator(head)))
    } else if (!is.null(body)) {
        converted <- goal_conversion(body)
        if (is.null(converted)) error <- type_error("callable", body) else body <- converted
    }
    if (!is.null(error)) {
        consultant$lines <- c(consultant$lines, paste0(file, ":", line, ": error: ", write_term(new_writer(), error)))
        consultant$counts[[file]][2L] <- consultant$counts[[file]][2L] + 1L
        return(invisible(NULL))
    }
    key <- indicator(head)
    previous <- consultant$database$predicates[[key]]
    if (file == "program.pl" && any(vapply(previous, function(clause) clause$file == "prelude.pl", logical(1L)))) {
        warning(consultant, file, line, paste("redefining prelude procedure", predicate_name(key)))
        consultant$database$predicates[[key]] <- list()
        previous <- list()
    }
    report_key <- paste0(file, ":", key)
    if (any(vapply(previous, function(clause) clause$file == file, logical(1L))) &&
        !identical(consultant$last[[file]], key) && !exists(report_key, consultant$discontiguous, inherits = FALSE)) {
        warning(consultant, file, line, paste("clauses of", predicate_name(key), "are not together"))
        consultant$discontiguous[[report_key]] <- TRUE
    }
    add_clause(consultant$database, list(head = head, body = body, file = file, line = line))
    consultant$last[[file]] <- key
    consultant$counts[[file]][1L] <- consultant$counts[[file]][1L] + 1L
    singletons <- Filter(function(name) !startsWith(name, "_") && reader$counts[[name]] == 1L, reader$count_order)
    repeated <- Filter(function(name) nchar(name) > 1L && startsWith(name, "_") && reader$counts[[name]] > 1L, reader$count_order)
    if (length(singletons)) warning(consultant, file, line, paste0("singleton variables: ", paste(singletons, collapse = ", ")))
    if (length(repeated)) warning(consultant, file, line, paste0("variables starting with _ occur more than once: ", paste(repeated, collapse = ", ")))
}
consult <- function(consultant, file, text) {
    reader <- new_reader(text)
    source_lines <- strsplit(text, "\n", fixed = TRUE)[[1L]]
    while (reader_token(reader)$kind != "eof") {
        line <- reader_token(reader)$line
        tryCatch({
            term <- read_clause(reader)
            consult_clause(consultant, term, file, line, reader)
        }, prolog_syntax_error = function(error) {
            token <- error$token
            consultant$counts[[file]][2L] <- consultant$counts[[file]][2L] + 1L
            consultant$lines <- c(consultant$lines, paste0(file, ":", token$line, ":", token$column, ": syntax error: ", error$message))
            if (token$kind != "eof") consultant$lines <- c(consultant$lines, paste0("    ", source_lines[token$line]), paste0(strrep(" ", token$column + 3L), "^"))
            reader$index <- token$index
            while (!reader_token(reader)$kind %in% c("end", "eof")) take_token(reader)
            if (reader_token(reader)$kind == "end") take_token(reader)
        })
    }
}
finish_consult <- function(consultant) {
    reported <- new_table()
    for (source in consultant$database$order) {
        for (clause in consultant$database$predicates[[source]]) {
            pending <- if (is.null(clause$body)) list() else list(clause$body)
            while (length(pending)) {
                term <- dereference(pending[[length(pending)]])
                pending[[length(pending)]] <- NULL
                if (is_variable(term) || is_integer(term)) next
                key <- indicator(term)
                if (key %in% predicate_keys(c(",", ";", "->"), 2L)) pending <- c(pending, rev(term$arguments)) else if (key %in% c(indicator_key("\\+", 1L), indicator_key("call", 1L))) {
                    pending[[length(pending) + 1L]] <- term$arguments[[1L]]
                } else if (key == indicator_key("findall", 3L)) pending[[length(pending) + 1L]] <- term$arguments[[2L]] else if (key == indicator_key("catch", 3L)) {
                    pending <- c(pending, list(term$arguments[[3L]], term$arguments[[1L]]))
                } else if (!key %in% c(CONTROLS, BUILTIN_PREDICATES) && !exists(key, consultant$database$predicates, inherits = FALSE) && !exists(key, reported, inherits = FALSE)) {
                    reported[[key]] <- TRUE
                    warning(consultant, clause$file, clause$line, paste("undefined procedure", predicate_name(key), "called from", predicate_name(source)))
                }
            }
        }
    }
    for (file in c("prelude.pl", "program.pl")) {
        counts <- consultant$counts[[file]]
        consultant$lines <- c(consultant$lines, paste0(file, ": clauses=", counts[1L], " errors=", counts[2L], " warnings=", counts[3L]))
    }
    count <- sum(vapply(consultant$database$order, function(key) length(consultant$database$predicates[[key]]), integer(1L)))
    consultant$lines <- c(consultant$lines, paste0("database: predicates=", length(consultant$database$order), " clauses=", count))
}
listing <- function(database) {
    lines <- character()
    for (key in database$order) {
        if (length(lines)) lines <- c(lines, "")
        for (clause in database$predicates[[key]]) {
            occurrences <- variables_in(clause$head, clause$body)
            counts <- new_table()
            for (variable in occurrences) {
                key <- variable_key(variable)
                counts[[key]] <- if (exists(key, counts, inherits = FALSE)) counts[[key]] + 1L else 1L
            }
            names <- new_table()
            number <- 0L
            for (variable in occurrences) {
                key <- variable_key(variable)
                if (exists(key, names, inherits = FALSE)) next
                if (counts[[key]] == 1L) names[[key]] <- "_" else {
                    suffix <- if (number < 26L) "" else as.character(number %/% 26L)
                    names[[key]] <- paste0(intToUtf8(65L + number %% 26L), suffix)
                    number <- number + 1L
                }
            }
            writer <- new_writer(names)
            head <- write_term(writer, clause$head)
            if (is.null(clause$body)) {
                lines <- c(lines, paste0(head, "."))
                next
            }
            lines <- c(lines, paste0(head, " :-"))
            goals <- list()
            body <- clause$body
            while (is_compound(body) && indicator(body) == indicator_key(",", 2L)) {
                goals[[length(goals) + 1L]] <- body$arguments[[1L]]
                body <- body$arguments[[2L]]
            }
            goals[[length(goals) + 1L]] <- body
            for (index in seq_along(goals)) lines <- c(lines, paste0("    ", write_term(writer, goals[[index]], 999L), if (index == length(goals)) "." else ","))
        }
    }
    lines
}
answer <- function(query_variables) {
    names <- new_table()
    for (entry in query_variables) {
        value <- dereference(entry$variable)
        if (is_variable(value) && !exists(variable_key(value), names, inherits = FALSE)) names[[variable_key(value)]] <- entry$name
    }
    writer <- new_writer(names)
    previous <- new_table()
    items <- character()
    for (entry in query_variables) {
        value <- dereference(entry$variable)
        if (is_variable(value)) {
            key <- variable_key(value)
            if (exists(key, previous, inherits = FALSE)) items <- c(items, paste(previous[[key]], "=", entry$name))
            previous[[key]] <- entry$name
        } else items <- c(items, paste(entry$name, "=", write_term(writer, value, 699L, TRUE)))
    }
    if (length(items)) paste(items, collapse = ", ") else "true"
}
marker <- function(kind, payload) list(kind = "marker", marker_kind = kind, payload = payload)
goal_entry <- function(goal, barrier, context) list(goal = goal, barrier = barrier, context = context)
prepend <- function(continuation, ...) {
    for (entry in rev(list(...))) continuation <- list(entry = entry, rest = continuation)
    continuation
}
new_engine <- function(database, query, variables, limit, calls, tries) {
    record(database = database, query_variables = variables, limit = limit, calls = calls, tries = tries,
        trail = new_trail(), goals = prepend(NULL, goal_entry(compound("call", query), 0L, NULL)), choices = new_table(), height = 0L,
        context = NULL, current_key = "", solutions = 0L, inferences = 0L, choicepoints = 0L, backtracks = 0L,
        answers = character(), output = character())
}
peek_choice <- function(engine) engine$choices[[as.character(engine$height)]]
pop_choice <- function(engine) {
    key <- as.character(engine$height)
    choice <- engine$choices[[key]]
    rm(list = key, envir = engine$choices)
    engine$height <- engine$height - 1L
    choice
}
cut_choices <- function(engine, height) while (engine$height > height) pop_choice(engine)
create_choice <- function(engine, kind, resume, ...) {
    choice <- record(kind = kind, mark = trail_mark(engine$trail), resume = resume, height = engine$height + 1L, ...)
    engine$height <- engine$height + 1L
    engine$choices[[as.character(engine$height)]] <- choice
    engine$choicepoints <- engine$choicepoints + 1L
    choice
}
count_value <- function(table, key) if (exists(key, table, inherits = FALSE)) table[[key]] else 0L
infer <- function(engine, key) {
    if (engine$inferences == 20000L) stop(structure(list(message = "inference limit"), class = c("inference_limit", "error", "condition")))
    engine$inferences <- engine$inferences + 1L
    engine$calls[[key]] <- count_value(engine$calls, key) + 1L
}
try_clause <- function(engine, clause, goal, barrier, context, continuation) {
    key <- indicator(goal)
    engine$tries[[key]] <- count_value(engine$tries, key) + 1L
    copied <- copy_clause(clause)
    if (!unify(engine$trail, copied[[1L]], goal)) return(FALSE)
    engine$goals <- if (is.null(copied[[2L]])) continuation else prepend(continuation, goal_entry(copied[[2L]], barrier, context))
    TRUE
}
user_call <- function(engine, goal, context) {
    key <- indicator(goal)
    if (!exists(key, engine$database$predicates, inherits = FALSE)) prolog_fault(compound("existence_error", atom_term("procedure"), indicator_term(key)))
    candidates <- candidate_clauses(engine$database, goal)
    if (!length(candidates)) return(FALSE)
    height <- engine$height
    if (length(candidates) > 1L) create_choice(engine, "CLAUSES", engine$goals, goal = goal, candidates = candidates, next_candidate = 2L, barrier = height, context = context)
    try_clause(engine, candidates[[1L]], goal, height, context, engine$goals)
}
control <- function(engine, goal, barrier, context) {
    key <- indicator(goal)
    args <- if (is_compound(goal)) goal$arguments else list()
    continuation <- engine$goals
    height <- engine$height
    if (key == indicator_key(",", 2L)) {
        engine$goals <- prepend(continuation, goal_entry(args[[1L]], barrier, context), goal_entry(args[[2L]], barrier, context))
    } else if (key == indicator_key("!", 0L)) cut_choices(engine, barrier) else if (key == indicator_key(";", 2L)) {
        create_choice(engine, "ALT", prepend(continuation, goal_entry(args[[2L]], barrier, context)))
        left <- dereference(args[[1L]])
        if (is_compound(left) && indicator(left) == indicator_key("->", 2L)) {
            engine$goals <- prepend(continuation, goal_entry(left$arguments[[1L]], height + 1L, context),
                goal_entry(marker("ITE", height), barrier, context), goal_entry(left$arguments[[2L]], barrier, context))
        } else engine$goals <- prepend(continuation, goal_entry(left, barrier, context))
    } else if (key == indicator_key("->", 2L)) {
        engine$goals <- prepend(continuation, goal_entry(args[[1L]], height, context),
            goal_entry(marker("ITE", height), barrier, context), goal_entry(args[[2L]], barrier, context))
    } else if (key == indicator_key("\\+", 1L)) {
        create_choice(engine, "ALT", continuation)
        engine$goals <- prepend(continuation, goal_entry(compound("call", args[[1L]]), barrier, context), goal_entry(marker("NAF", height), barrier, context))
    } else if (indicator_parts(key)$name == "call") {
        target <- dereference(args[[1L]])
        if (is_variable(target)) prolog_fault(atom_term("instantiation_error"))
        if (is_integer(target)) prolog_fault(type_error("callable", target))
        if (length(args) > 1L) target <- if (is_atom(target)) compound_term(target$name, args[-1L]) else compound_term(target$name, c(target$arguments, args[-1L]))
        converted <- goal_conversion(target)
        if (is.null(converted)) prolog_fault(type_error("callable", target))
        engine$goals <- prepend(continuation, goal_entry(converted, height, context))
    } else {
        frame <- create_choice(engine, "CATCH", continuation, catcher = args[[2L]], recovery = args[[3L]], parent = context)
        engine$goals <- prepend(continuation, goal_entry(compound("call", args[[1L]]), barrier, frame), goal_entry(marker("EXIT", frame), barrier, context))
    }
    TRUE
}
execute_marker <- function(engine, marker) {
    kind <- marker$marker_kind
    payload <- marker$payload
    if (kind %in% c("ITE", "NAF")) {
        cut_choices(engine, payload)
        return(kind == "ITE")
    }
    if (kind == "EXIT") {
        if (engine$height > 0L && identical(peek_choice(engine), payload)) pop_choice(engine)
        return(TRUE)
    }
    payload$results[[length(payload$results) + 1L]] <- copy_term(payload$template)
    FALSE
}
between <- function(engine, args) {
    lower <- require_integer(args[[1L]])
    upper <- require_integer(args[[2L]])
    value <- dereference(args[[3L]])
    if (!is_variable(value) && !is_integer(value)) prolog_fault(type_error("integer", value))
    if (is_integer(value)) return(lower <= value$value && value$value <= upper)
    if (lower > upper) return(FALSE)
    if (lower < upper) create_choice(engine, "BETWEEN", engine$goals, upper = upper, target = value, next_value = lower + 1L)
    unify(engine$trail, value, integer_term(lower))
}
length_predicate <- function(engine, args) {
    sequence <- args[[1L]]
    number <- dereference(args[[2L]])
    if (!is_variable(number) && !is_integer(number)) prolog_fault(type_error("integer", number))
    if (is_integer(number) && number$value < 0L) prolog_fault(domain_error("not_less_than_zero", number))
    parts <- list_parts(sequence)
    count <- length(parts$elements)
    if (is_atom(parts$tail, "[]")) return(unify(engine$trail, number, integer_term(count)))
    if (!is_variable(parts$tail)) prolog_fault(type_error("list", sequence))
    if (is_integer(number)) {
        if (number$value < count) return(FALSE)
        elements <- lapply(seq_len(as.integer(number$value) - count), function(unused) variable_term())
        return(unify(engine$trail, parts$tail, make_list(elements)))
    }
    create_choice(engine, "LENGTH", engine$goals, tail = parts$tail, number = number, count = count, next_value = count + 1L)
    unify(engine$trail, parts$tail, NIL) && unify(engine$trail, number, integer_term(count))
}
step <- function(engine) {
    entry <- engine$goals$entry
    engine$goals <- engine$goals$rest
    goal <- entry$goal
    barrier <- entry$barrier
    context <- entry$context
    engine$context <- context
    if (identical(goal$kind, "marker")) return(execute_marker(engine, goal))
    goal <- dereference(goal)
    key <- indicator(goal)
    engine$current_key <- key
    if (key %in% CONTROLS) return(control(engine, goal, barrier, context))
    infer(engine, key)
    if (key == indicator_key("findall", 3L)) {
        frame <- create_choice(engine, "FINDALL", engine$goals, template = goal$arguments[[1L]], result = goal$arguments[[3L]], results = list())
        engine$goals <- prepend(NULL, goal_entry(compound("call", goal$arguments[[2L]]), barrier, context), goal_entry(marker("COLLECT", frame), barrier, context))
        return(TRUE)
    }
    if (key == indicator_key("throw", 1L)) {
        ball <- dereference(goal$arguments[[1L]])
        if (is_variable(ball)) prolog_fault(atom_term("instantiation_error"))
        prolog_ball(ball)
    }
    if (key == indicator_key("between", 3L)) return(between(engine, goal$arguments))
    if (key == indicator_key("length", 2L)) return(length_predicate(engine, goal$arguments))
    if (key %in% DETERMINISTIC) {
        output <- function(term, quoted) {
            text <- if (is.null(term)) "\n" else write_term(new_writer(quoted = quoted), term)
            engine$output <- c(engine$output, text)
        }
        return(execute_deterministic(goal, engine$trail, output))
    }
    user_call(engine, goal, context)
}
backtrack <- function(engine) {
    repeat {
        engine$backtracks <- engine$backtracks + 1L
        while (engine$height > 0L) {
            choice <- peek_choice(engine)
            undo(engine$trail, choice$mark)
            if (choice$kind == "CATCH") pop_choice(engine) else break
        }
        if (engine$height == 0L) return(FALSE)
        choice <- peek_choice(engine)
        if (choice$kind == "ALT") {
            pop_choice(engine)
            engine$goals <- choice$resume
            return(TRUE)
        }
        if (choice$kind == "CLAUSES") {
            clause <- choice$candidates[[choice$next_candidate]]
            if (choice$next_candidate == length(choice$candidates)) pop_choice(engine) else choice$next_candidate <- choice$next_candidate + 1L
            if (try_clause(engine, clause, choice$goal, choice$barrier, choice$context, choice$resume)) return(TRUE)
        } else if (choice$kind == "BETWEEN") {
            infer(engine, indicator_key("between", 3L))
            value <- choice$next_value
            if (value == choice$upper) pop_choice(engine) else choice$next_value <- value + 1L
            if (unify(engine$trail, choice$target, integer_term(value))) {
                engine$goals <- choice$resume
                return(TRUE)
            }
        } else if (choice$kind == "LENGTH") {
            infer(engine, indicator_key("length", 2L))
            count <- choice$next_value
            choice$next_value <- count + 1L
            value <- make_list(lapply(seq_len(count - choice$count), function(unused) variable_term()))
            if (unify(engine$trail, choice$tail, value) && unify(engine$trail, choice$number, integer_term(count))) {
                engine$goals <- choice$resume
                return(TRUE)
            }
        } else if (choice$kind == "FINDALL") {
            pop_choice(engine)
            if (unify(engine$trail, make_list(choice$results), choice$result)) {
                engine$goals <- choice$resume
                return(TRUE)
            }
        }
    }
}
handle_exception <- function(engine, ball) {
    ball <- copy_term(ball)
    frame <- engine$context
    while (!is.null(frame)) {
        cut_choices(engine, frame$height - 1L)
        undo(engine$trail, frame$mark)
        mark <- trail_mark(engine$trail)
        if (unify(engine$trail, copy_term(ball), frame$catcher)) {
            engine$goals <- prepend(frame$resume, goal_entry(compound("call", frame$recovery), engine$height, frame$parent))
            return(TRUE)
        }
        undo(engine$trail, mark)
        frame <- frame$parent
    }
    engine$answers <- c(engine$answers, paste0("uncaught exception: ", write_term(new_writer(), ball)))
    FALSE
}
run_query <- function(engine) {
    repeat {
        outcome <- tryCatch({
            if (is.null(engine$goals)) {
                engine$solutions <- engine$solutions + 1L
                text <- answer(engine$query_variables)
                if ((!is.null(engine$limit) && engine$solutions == engine$limit) || engine$height == 0L) {
                    engine$answers <- c(engine$answers, paste0(text, "."))
                    "done"
                } else {
                    engine$answers <- c(engine$answers, paste0(text, " ;"))
                    if (backtrack(engine)) "continue" else {
                        engine$answers <- c(engine$answers, "false.")
                        "done"
                    }
                }
            } else if (!step(engine) && !backtrack(engine)) {
                engine$answers <- c(engine$answers, "false.")
                "done"
            } else "continue"
        }, prolog_fault = function(error) {
            if (handle_exception(engine, compound("error", error$term, indicator_term(engine$current_key)))) "continue" else "done"
        }, prolog_ball = function(error) {
            if (handle_exception(engine, error$term)) "continue" else "done"
        }, inference_limit = function(error) {
            engine$answers <- c(engine$answers, "inference limit exceeded")
            "done"
        })
        if (outcome == "done") break
    }
    c(engine$solutions, engine$inferences, engine$choicepoints, engine$backtracks)
}
statistics <- function(prefix, counts) {
    paste0(prefix, " solutions=", counts[1L], " inferences=", counts[2L], " choicepoints=", counts[3L], " backtracks=", counts[4L])
}
read_text <- function(path) {
    lines <- readLines(path, warn = FALSE)
    if (length(lines)) paste0(paste0(lines, collapse = "\n"), "\n") else ""
}
main <- function() {
    options(expressions = 100000L)
    consultant <- new_consultant()
    for (file in c("prelude.pl", "program.pl")) consult(consultant, file, read_text(file.path("input", file)))
    finish_consult(consultant)
    answers <- writes <- stats <- character()
    calls <- new_table()
    tries <- new_table()
    totals <- integer(4L)
    queries <- readLines("input/queries.txt", warn = FALSE)
    for (number in seq_along(queries)) {
        source <- queries[number]
        answers <- c(answers, source)
        writes <- c(writes, paste0("== query ", number, " ==\n"))
        marker <- which(strsplit(source, "", fixed = TRUE)[[1L]] == "?")[1L]
        limit <- if (marker == 1L) NULL else as.integer(trimws(substr(source, 1L, marker - 1L)))
        body_start <- marker + 3L
        reader <- new_reader(substring(source, body_start), body_start)
        parsed <- tryCatch(list(term = read_clause(reader, TRUE)), prolog_syntax_error = function(error) list(error = error))
        if (!is.null(parsed$error)) {
            answers <- c(answers, paste0("syntax error at column ", parsed$error$token$column, ": ", parsed$error$message))
            stats <- c(stats, paste0("query ", number, ": syntax error"))
            next
        }
        names <- reader$name_order[!startsWith(reader$name_order, "_")]
        variables <- lapply(names, function(name) list(name = name, variable = reader$names[[name]]))
        engine <- new_engine(consultant$database, parsed$term, variables, limit, calls, tries)
        counts <- run_query(engine)
        totals <- totals + counts
        answers <- c(answers, engine$answers)
        text <- paste0(engine$output, collapse = "")
        writes <- c(writes, paste0(text, if (text != "" && !endsWith(text, "\n")) "\n" else ""))
        stats <- c(stats, statistics(paste0("query ", number, ":"), counts))
    }
    stats <- c(stats, statistics("total:", totals), "== profile ==")
    keys <- ls(calls, all.names = TRUE)
    counts <- vapply(keys, function(key) calls[[key]], integer(1L))
    names <- vapply(keys, predicate_name, character(1L))
    keys <- keys[order(-counts, names, method = "radix")]
    for (key in keys) {
        line <- paste0(predicate_name(key), " calls=", calls[[key]])
        if (exists(key, consultant$database$predicates, inherits = FALSE)) line <- paste0(line, " tries=", count_value(tries, key))
        stats <- c(stats, line)
    }
    reports <- list("consult.txt" = consultant$lines, "listing.txt" = listing(consultant$database), "answers.txt" = answers, "stats.txt" = stats)
    for (name in names(reports)) writeLines(reports[[name]], file.path("output", name), useBytes = TRUE)
    writeChar(paste0(writes, collapse = ""), "output/write_output.txt", eos = NULL, useBytes = TRUE)
}
main()
