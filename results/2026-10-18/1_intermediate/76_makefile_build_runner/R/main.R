options(scipen = 999)
emit <- function(...) cat(paste0(...), "\n", sep = "")
trim <- function(text) sub(" +\\z", "", sub("\\A +", "", text, perl = TRUE), perl = TRUE)
words <- function(text) {
    result <- strsplit(text, " ", fixed = TRUE)[[1]]
    result[nzchar(result)]
}
part <- function(text, start, end = nchar(text, type = "bytes")) {
    if (end <= start) "" else substr(text, start + 1L, end)
}
at <- function(text, i) part(text, i, i + 1L)
ascii_sort <- function(values) sort(values, method = "radix")
unique_words <- function(values) values[!duplicated(values)]

make_workbench <- function(files) {
    state <- new.env(parent = emptyenv())
    state$files <- files
    state$clock <- if (length(files) == 0) 0 else max(unlist(files))
    state$location <- "make"
    state$scopes <- list()
    state$active <- list()
    state$automatic <- NULL
    functions <- list(
        subst = c(3, 3), patsubst = c(3, 3), strip = c(1, 1),
        findstring = c(2, 2), filter = c(2, 2), "filter-out" = c(2, 2),
        sort = c(1, 1), word = c(2, 2), wordlist = c(3, 3),
        words = c(1, 1), firstword = c(1, 1), lastword = c(1, 1),
        dir = c(1, 1), notdir = c(1, 1), suffix = c(1, 1),
        basename = c(1, 1), addsuffix = c(2, 2), addprefix = c(2, 2),
        wildcard = c(1, 1), foreach = c(3, 3), "if" = c(2, 3),
        call = c(1, Inf), value = c(1, 1), info = c(1, 1),
        warning = c(1, 1), error = c(1, 1)
    )
    error <- function(reason) {
        stop(structure(list(message = reason, call = NULL, location = state$location), class = c("make_error", "error", "condition")))
    }
    abort_build <- function() stop(structure(list(message = "", call = NULL), class = c("build_abort", "error", "condition")))
    report <- function(error) emit(error$location, ": *** ", conditionMessage(error), ".  Stop.")
    clear_makefile <- function() {
        state$loaded <- FALSE
        state$variables <- list()
        state$rules <- list()
        state$patterns <- list()
        state$phony <- character()
        state$default <- NULL
    }
    clear_makefile()
    closing <- function(text, opening) {
        left <- at(text, opening)
        right <- if (left == "(") ")" else "}"
        depth <- 0
        for (i in seq.int(opening, nchar(text) - 1L)) {
            char <- at(text, i)
            if (char == left) depth <- depth + 1
            if (char == right) depth <- depth - 1
            if (depth == 0) return(i)
        }
        error("unterminated variable reference")
    }
    outside <- function(text) {
        result <- list()
        i <- 0
        while (i < nchar(text)) {
            char <- at(text, i)
            if (char == "$") {
                i <- if (at(text, i + 1L) %in% c("(", "{")) closing(text, i + 1L) + 1L else i + 2L
            } else {
                if (is.null(result[[char]])) result[[char]] <- i
                i <- i + 1L
            }
        }
        result
    }
    stem <- function(pattern, text) {
        position <- regexpr("%", pattern, fixed = TRUE)[1]
        if (position < 0) return(if (pattern == text) "" else NULL)
        left <- part(pattern, 0, position - 1L)
        right <- part(pattern, position)
        if (nchar(text) < nchar(left) + nchar(right) || !startsWith(text, left) || !endsWith(text, right)) return(NULL)
        part(text, nchar(left), nchar(text) - nchar(right))
    }
    substitute <- function(text, value) {
        position <- regexpr("%", text, fixed = TRUE)[1]
        if (position < 0) text else paste0(part(text, 0, position - 1L), value, part(text, position))
    }
    replace <- function(word, pattern, replacement) {
        value <- stem(pattern, word)
        if (is.null(value)) return(word)
        if (grepl("%", pattern, fixed = TRUE)) substitute(replacement, value) else replacement
    }
    wildcard <- function(pattern) {
        if (!grepl("*", pattern, fixed = TRUE) && !grepl("?", pattern, fixed = TRUE)) {
            return(if (!is.null(state$files[[pattern]])) pattern else character())
        }
        chars <- strsplit(pattern, "", fixed = TRUE)[[1]]
        quoted <- vapply(chars, function(char) {
            if (char == "*") "[^/]*" else if (char == "?") "[^/]" else if (char %in% c("\\", ".", "+", "[", "]", "(", ")", "{", "}", "^", "$", "|")) paste0("\\", char) else char
        }, character(1))
        regex <- paste0("\\A", paste0(quoted, collapse = ""), "\\z")
        names <- names(state$files)
        ascii_sort(names[grepl(regex, names, perl = TRUE)])
    }
    with_scope <- function(scope, action) {
        state$scopes[[length(state$scopes) + 1L]] <- scope
        on.exit(state$scopes <- head(state$scopes, -1L))
        action()
    }
    variable_value <- function(name) {
        variable <- state$variables[[name]]
        if (is.null(variable)) return("")
        if (variable$kind == ":=") return(variable$value)
        if (!is.null(state$active[[name]])) error(paste0("Recursive variable '", name, "' references itself (eventually)"))
        state$active[[name]] <- TRUE
        on.exit(state$active[[name]] <- NULL)
        expand(variable$value)
    }
    reference_value <- function(name) {
        for (i in rev(seq_along(state$scopes))) {
            scope <- state$scopes[[i]]
            if (scope$type == "foreach") {
                if (scope$name == name) return(scope$value)
            } else if (grepl("\\A[0-9]+\\z", name, perl = TRUE)) {
                index <- as.integer(name) + 1L
                return(if (index <= length(scope$values)) scope$values[index] else "")
            }
        }
        if (!is.null(state$automatic) && name %in% names(state$automatic)) return(state$automatic[[name]])
        variable_value(name)
    }
    expand <- function(text) {
        result <- character()
        i <- 0
        while (i < nchar(text)) {
            next_char <- at(text, i + 1L)
            if (at(text, i) != "$") {
                result <- c(result, at(text, i))
                i <- i + 1L
            } else if (next_char == "$") {
                result <- c(result, "$")
                i <- i + 2L
            } else if (next_char %in% c("(", "{")) {
                finish <- closing(text, i + 1L)
                result <- c(result, reference(part(text, i + 2L, finish), next_char))
                i <- finish + 1L
            } else {
                if (nzchar(next_char)) result <- c(result, reference_value(next_char))
                i <- i + 2L
            }
        }
        paste0(result, collapse = "")
    }
    reference <- function(content, bracket) {
        space <- regexpr(" ", content, fixed = TRUE)[1]
        name <- if (space > 0) part(content, 0, space - 1L) else ""
        if (space > 0 && name %in% names(functions)) return(apply_function(name, sub("\\A +", "", part(content, space), perl = TRUE), bracket))
        name <- expand(content)
        colon <- regexpr(":", name, fixed = TRUE)[1]
        equals <- if (colon > 0) regexpr("=", part(name, colon), fixed = TRUE)[1] else -1L
        if (equals < 0) return(reference_value(name))
        equals <- equals + colon
        variable <- part(name, 0, colon - 1L)
        pattern <- part(name, colon, equals - 1L)
        replacement <- part(name, equals)
        if (!grepl("%", pattern, fixed = TRUE)) {
            pattern <- paste0("%", pattern)
            replacement <- paste0("%", replacement)
        }
        paste(vapply(words(reference_value(variable)), function(word) replace(word, pattern, replacement), character(1)), collapse = " ")
    }
    literal_replace <- function(text, from, to) {
        if (!nzchar(from)) return(text)
        matches <- gregexpr(from, text, fixed = TRUE)[[1]]
        if (matches[1] < 0) return(text)
        result <- character()
        start <- 0
        for (position in matches) {
            result <- c(result, part(text, start, position - 1L), to)
            start <- position - 1L + nchar(from)
        }
        paste0(c(result, part(text, start)), collapse = "")
    }
    apply_function <- function(name, text, bracket) {
        limits <- functions[[name]]
        args <- character()
        depth <- start <- 0
        close <- if (bracket == "(") ")" else "}"
        for (i in seq_len(nchar(text)) - 1L) {
            char <- at(text, i)
            if (char == bracket) depth <- depth + 1
            if (char == close) depth <- depth - 1
            if (char == "," && depth == 0 && length(args) < limits[2] - 1) {
                args <- c(args, part(text, start, i))
                start <- i + 1L
            }
        }
        args <- c(args, part(text, start))
        if (length(args) < limits[1]) error(paste0("insufficient number of arguments (", length(args), ") to function '", name, "'"))
        if (name == "foreach") {
            variable <- trim(expand(args[1]))
            list <- words(expand(args[2]))
            result <- vapply(list, function(word) with_scope(list(type = "foreach", name = variable, value = word), function() expand(args[3])), character(1))
            return(paste(result, collapse = " "))
        }
        if (name == "if") {
            condition <- trim(expand(args[1]))
            return(expand(if (nzchar(condition)) args[2] else if (length(args) >= 3) args[3] else ""))
        }
        if (name == "call") {
            values <- vapply(args, expand, character(1))
            variable <- trim(values[1])
            entry <- state$variables[[variable]]
            if (is.null(entry)) return("")
            if (entry$kind == ":=") return(entry$value)
            return(with_scope(list(type = "call", values = c(variable, values[-1])), function() expand(entry$value)))
        }
        values <- vapply(args, expand, character(1))
        if (name != "subst") values <- vapply(values, trim, character(1))
        a <- values[1]
        b <- if (length(values) >= 2) values[2] else ""
        c <- if (length(values) >= 3) values[3] else ""
        if (name == "subst") return(literal_replace(c, a, b))
        if (name == "patsubst") return(paste(vapply(words(c), function(word) replace(word, a, b), character(1)), collapse = " "))
        if (name == "strip") return(paste(words(a), collapse = " "))
        if (name == "findstring") return(if (grepl(a, b, fixed = TRUE)) a else "")
        if (name %in% c("filter", "filter-out")) {
            patterns <- words(a)
            list <- words(b)
            matches <- vapply(list, function(word) any(vapply(patterns, function(pattern) !is.null(stem(pattern, word)), logical(1))), logical(1))
            return(paste(list[matches == (name == "filter")], collapse = " "))
        }
        if (name == "sort") return(paste(ascii_sort(unique_words(words(a))), collapse = " "))
        if (name == "word") {
            if (!grepl("\\A[0-9]+\\z", a, perl = TRUE)) error(paste0("non-numeric first argument to 'word' function: '", a, "'"))
            index <- as.integer(a)
            if (index == 0) error("first argument to 'word' function must be greater than 0")
            list <- words(b)
            return(if (index <= length(list)) list[index] else "")
        }
        if (name == "wordlist") {
            if (!grepl("\\A[0-9]+\\z", a, perl = TRUE)) error(paste0("non-numeric first argument to 'wordlist' function: '", a, "'"))
            if (!grepl("\\A[0-9]+\\z", b, perl = TRUE)) error(paste0("non-numeric second argument to 'wordlist' function: '", b, "'"))
            start <- as.integer(a)
            end <- as.integer(b)
            if (start == 0) error(paste0("invalid first argument to 'wordlist' function: '", a, "'"))
            list <- words(c)
            end <- min(end, length(list))
            return(if (start > end) "" else paste(list[seq.int(start, end)], collapse = " "))
        }
        if (name == "words") return(as.character(length(words(a))))
        if (name == "firstword") return(if (length(words(a)) > 0) words(a)[1] else "")
        if (name == "lastword") return(if (length(words(a)) > 0) tail(words(a), 1) else "")
        if (name %in% c("dir", "notdir", "suffix", "basename")) {
            result <- character()
            for (word in words(a)) {
                slashes <- gregexpr("/", word, fixed = TRUE)[[1]]
                dots <- gregexpr(".", word, fixed = TRUE)[[1]]
                slash <- max(slashes)
                dot <- max(dots)
                extension <- dot > 0 && dot > slash
                if (name == "dir") {
                    result <- c(result, if (slash < 0) "./" else part(word, 0, slash))
                } else if (name == "notdir") {
                    result <- c(result, if (slash < 0) word else part(word, slash))
                } else if (name == "basename") {
                    result <- c(result, if (extension) part(word, 0, dot - 1L) else word)
                } else if (extension) {
                    result <- c(result, part(word, dot - 1L))
                }
            }
            return(paste(result, collapse = " "))
        }
        if (name == "addsuffix") return(paste(vapply(words(b), function(word) paste0(word, a), character(1)), collapse = " "))
        if (name == "addprefix") return(paste(vapply(words(b), function(word) paste0(a, word), character(1)), collapse = " "))
        if (name == "wildcard") return(paste(unlist(lapply(words(a), wildcard), use.names = FALSE), collapse = " "))
        if (name == "value") return(if (is.null(state$variables[[a]])) "" else state$variables[[a]]$value)
        if (name == "info") emit(a)
        if (name == "warning") emit(state$location, ": ", a)
        if (name == "error") error(a)
        ""
    }
    new_rule <- function(target, prerequisites = character()) {
        rule <- new.env(parent = emptyenv())
        rule$target <- target
        rule$prerequisites <- prerequisites
        rule$recipe <- NULL
        rule$stem <- ""
        rule
    }
    register <- function(target, prerequisites) {
        if (is.null(state$rules[[target]])) state$rules[[target]] <- new_rule(target)
        rule <- state$rules[[target]]
        rule$prerequisites <- unique_words(c(rule$prerequisites, prerequisites))
        if (is.null(state$default) && !startsWith(target, ".")) state$default <- target
        rule
    }
    add_recipe <- function(current, number, text) {
        if (is.null(current)) error("recipe commences before first target")
        if (length(current$entries) == 0) return(invisible(NULL))
        if (is.null(current$recipe)) {
            recipe <- new.env(parent = emptyenv())
            recipe$lines <- list()
            for (rule in current$entries) {
                if (current$explicit && !is.null(rule$recipe)) {
                    emit("Makefile:", number, ": warning: overriding recipe for target '", rule$target, "'")
                    emit("Makefile:", rule$recipe$lines[[1]]$number, ": warning: ignoring old recipe for target '", rule$target, "'")
                }
                rule$recipe <- recipe
            }
            current$recipe <- recipe
        }
        current$recipe$lines[[length(current$recipe$lines) + 1L]] <- list(number = number, text = text)
    }
    parse_rule <- function(text, colon, number) {
        targets <- unique_words(words(expand(part(text, 0, colon))))
        rest <- part(text, colon + 1L)
        semicolon <- outside(rest)[[";"]]
        inline <- if (is.null(semicolon)) NULL else sub("\\A +", "", part(rest, semicolon + 1L), perl = TRUE)
        if (!is.null(semicolon)) rest <- part(rest, 0, semicolon)
        second <- outside(rest)[[":"]]
        pattern <- if (is.null(second)) NULL else trim(expand(part(rest, 0, second)))
        if (!is.null(second)) rest <- part(rest, second + 1L)
        prerequisites <- words(expand(rest))
        entries <- list()
        explicit <- TRUE
        if (identical(targets, ".PHONY")) {
            state$phony <- unique_words(c(state$phony, prerequisites))
        } else if (!is.null(pattern)) {
            if (!grepl("%", pattern, fixed = TRUE)) error("target pattern contains no '%'")
            for (target in targets) {
                value <- stem(pattern, target)
                if (!is.null(value) && nzchar(value)) {
                    entry <- register(target, vapply(prerequisites, function(p) substitute(p, value), character(1)))
                    entry$stem <- value
                    entries[[length(entries) + 1L]] <- entry
                } else {
                    emit("Makefile:", number, ": target '", target, "' doesn't match the target pattern")
                }
            }
        } else if (any(grepl("%", targets, fixed = TRUE))) {
            if (!all(grepl("%", targets, fixed = TRUE))) error("mixed implicit and normal rules")
            explicit <- FALSE
            for (target in targets) {
                entry <- new_rule(target, prerequisites)
                state$patterns[[length(state$patterns) + 1L]] <- entry
                entries[[length(entries) + 1L]] <- entry
            }
        } else {
            entries <- lapply(targets, function(target) register(target, prerequisites))
        }
        current <- new.env(parent = emptyenv())
        current$entries <- entries
        current$explicit <- explicit
        current$recipe <- NULL
        if (!is.null(inline)) add_recipe(current, number, inline)
        current
    }
    load_makefile <- function(body) {
        clear_makefile()
        on.exit(state$location <- "make")
        tryCatch({
            current <- NULL
            conditions <- list()
            i <- 1L
            while (i <= length(body)) {
                number <- i
                state$location <- paste0("Makefile:", number)
                top <- if (length(conditions) == 0) NULL else tail(conditions, 1)[[1]]
                active <- is.null(top) || (top$outer && top$value)
                text <- body[i]
                i <- i + 1L
                if (startsWith(text, ">")) {
                    if (active) add_recipe(current, number, sub("\\A +", "", part(text, 1), perl = TRUE))
                    next
                }
                while (endsWith(text, "\\") && i <= length(body)) {
                    text <- paste0(sub(" +\\z", "", part(text, 0, nchar(text) - 1L), perl = TRUE), " ", sub("\\A +", "", body[i], perl = TRUE))
                    i <- i + 1L
                }
                hash <- regexpr("#", text, fixed = TRUE)[1]
                if (hash > 0) text <- part(text, 0, hash - 1L)
                text <- trim(text)
                space <- regexpr(" ", text, fixed = TRUE)[1]
                first <- if (space < 0) text else part(text, 0, space - 1L)
                rest <- if (space < 0) "" else trim(part(text, space))
                if (first %in% c("ifdef", "ifndef", "ifeq", "ifneq")) {
                    value <- FALSE
                    if (active) {
                        if (first %in% c("ifdef", "ifndef")) {
                            variable <- state$variables[[trim(expand(rest))]]
                            value <- !is.null(variable) && nzchar(variable$value)
                            if (first == "ifndef") value <- !value
                        } else {
                            if (nchar(rest) < 2 || !startsWith(rest, "(") || !endsWith(rest, ")")) error("invalid syntax in conditional")
                            inner <- part(rest, 1, nchar(rest) - 1L)
                            depth <- 0
                            comma <- NULL
                            for (p in seq_len(nchar(inner)) - 1L) {
                                char <- at(inner, p)
                                if (char == "(") depth <- depth + 1
                                if (char == ")") depth <- depth - 1
                                if (char == "," && depth == 0) {
                                    comma <- p
                                    break
                                }
                            }
                            if (is.null(comma)) error("invalid syntax in conditional")
                            left <- trim(expand(part(inner, 0, comma)))
                            right <- trim(expand(part(inner, comma + 1L)))
                            value <- left == right
                            if (first == "ifneq") value <- !value
                        }
                    }
                    conditions[[length(conditions) + 1L]] <- list(outer = active, value = value, seen_else = FALSE, number = number)
                } else if (first == "else") {
                    if (length(conditions) == 0) error("extraneous 'else'")
                    p <- length(conditions)
                    if (conditions[[p]]$seen_else) error("only one 'else' per conditional")
                    conditions[[p]]$value <- !conditions[[p]]$value
                    conditions[[p]]$seen_else <- TRUE
                } else if (first == "endif") {
                    if (length(conditions) == 0) error("extraneous 'endif'")
                    conditions <- head(conditions, -1L)
                } else if (active && nzchar(text)) {
                    positions <- outside(text)
                    equals <- positions[["="]]
                    colon <- positions[[":"]]
                    if (!is.null(equals) && (is.null(colon) || colon >= equals - 1L)) {
                        operator_start <- if (equals > 0 && at(text, equals - 1L) %in% c(":", "+", "?")) equals - 1L else equals
                        operator <- part(text, operator_start, equals + 1L)
                        variable <- trim(part(text, 0, operator_start))
                        if (!nzchar(variable)) error("empty variable name")
                        rhs <- trim(part(text, equals + 1L))
                        old <- state$variables[[variable]]
                        if (operator == ":=") {
                            state$variables[[variable]] <- list(kind = ":=", value = expand(rhs))
                        } else if (operator == "+=" && !is.null(old)) {
                            addition <- if (old$kind == ":=") expand(rhs) else rhs
                            state$variables[[variable]] <- list(kind = old$kind, value = if (!nzchar(old$value)) addition else paste0(old$value, " ", addition))
                        } else if (operator != "?=" || is.null(old)) {
                            state$variables[[variable]] <- list(kind = "=", value = rhs)
                        }
                        current <- NULL
                    } else if (!is.null(colon)) {
                        current <- parse_rule(text, colon, number)
                    } else if (nzchar(trim(expand(text)))) {
                        error("missing separator")
                    }
                }
            }
            if (length(conditions) > 0) {
                state$location <- paste0("Makefile:", tail(conditions, 1)[[1]]$number)
                error("missing 'endif'")
            }
            state$loaded <- TRUE
            patterns <- sum(vapply(state$patterns, function(rule) !is.null(rule$recipe), logical(1)))
            emit("Makefile loaded: lines=", length(body), " variables=", length(state$variables), " targets=", length(state$rules), " patterns=", patterns, " goal=", if (is.null(state$default)) "(none)" else state$default)
        }, make_error = function(error) {
            report(error)
            clear_makefile()
        })
    }
    new_time <- function(name) {
        state$clock <- state$clock + 1
        state$files[[name]] <- state$clock
    }
    remove_file <- function(name, forced = FALSE) {
        if (!is.null(state$files[[name]])) {
            state$files[[name]] <- NULL
            return(0)
        }
        if (forced) return(0)
        emit("rm: cannot remove '", name, "': No such file or directory")
        1
    }
    determine <- function(target) {
        explicit <- state$rules[[target]]
        if (!is.null(explicit) && !is.null(explicit$recipe)) return(list(prerequisites = explicit$prerequisites, recipe = explicit$recipe, stem = explicit$stem, kind = "rule"))
        if (!(target %in% state$phony)) {
            candidates <- list()
            for (i in seq_along(state$patterns)) {
                rule <- state$patterns[[i]]
                value <- if (is.null(rule$recipe)) NULL else stem(rule$target, target)
                if (!is.null(value) && nzchar(value)) candidates[[length(candidates) + 1L]] <- list(size = nchar(value), index = i, rule = rule, stem = value)
            }
            if (length(candidates) > 0) {
                candidates <- candidates[order(vapply(candidates, function(c) c$size, numeric(1)), vapply(candidates, function(c) c$index, numeric(1)))]
            }
            for (candidate in candidates) {
                prerequisites <- vapply(candidate$rule$prerequisites, function(p) substitute(p, candidate$stem), character(1))
                usable <- all(vapply(prerequisites, function(p) !is.null(state$files[[p]]) || !is.null(state$rules[[p]]), logical(1)))
                if (usable) {
                    extra <- if (is.null(explicit)) character() else explicit$prerequisites
                    return(list(prerequisites = unique_words(c(prerequisites, extra)), recipe = candidate$rule$recipe, stem = candidate$stem, kind = "rule"))
                }
            }
        }
        if (!is.null(explicit) || target %in% state$phony) {
            return(list(prerequisites = if (is.null(explicit)) character() else explicit$prerequisites, recipe = NULL, stem = if (is.null(explicit)) "" else explicit$stem, kind = "rule"))
        }
        list(prerequisites = character(), recipe = NULL, stem = "", kind = if (!is.null(state$files[[target]])) "source" else "missing")
    }
    target_time <- function(target) if (target %in% state$phony) NULL else state$files[[target]]
    simulate <- function(command) {
        parts <- words(command)
        first <- parts[1]
        parts <- parts[-1]
        if (first == "echo") {
            emit(paste(parts, collapse = " "))
        } else if (first == "touch") {
            for (name in parts) new_time(name)
        } else if (first == "rm") {
            forced <- length(parts) > 0 && parts[1] == "-f"
            if (forced) parts <- parts[-1]
            result <- 0
            for (pattern in parts) {
                matches <- wildcard(pattern)
                if (length(matches) == 0) matches <- pattern
                for (name in matches) result <- max(result, remove_file(name, forced))
            }
            return(result)
        } else if (first == "false") {
            return(1)
        } else if (first == "exit") {
            return(if (length(parts) == 0) 0 else as.integer(parts[1]))
        }
        0
    }
    run_recipe <- function(target, prerequisites, recipe, value, newer, options) {
        state$automatic <- list("@" = target, "<" = if (length(prerequisites) == 0) "" else prerequisites[1], "^" = paste(prerequisites, collapse = " "), "?" = paste(newer, collapse = " "), "*" = value)
        on.exit({
            state$automatic <- NULL
            state$location <- "make"
        })
        expanded <- lapply(recipe$lines, function(line) {
            state$location <- paste0("Makefile:", line$number)
            list(number = line$number, text = expand(line$text))
        })
        for (line in expanded) {
            text <- line$text
            prefix_length <- 0L
            while (prefix_length < nchar(text) && at(text, prefix_length) %in% c(" ", "@", "-")) prefix_length <- prefix_length + 1L
            prefix <- part(text, 0, prefix_length)
            command <- sub(" +\\z", "", part(text, prefix_length), perl = TRUE)
            if (!nzchar(command)) next
            if ("n" %in% options || (!grepl("@", prefix, fixed = TRUE) && !("s" %in% options))) emit(command)
            if ("n" %in% options) next
            code <- simulate(command)
            if (code == 0) next
            if (grepl("-", prefix, fixed = TRUE) || "i" %in% options) {
                emit("make: [Makefile:", line$number, ": ", target, "] Error ", code, " (ignored)")
            } else {
                emit("make: *** [Makefile:", line$number, ": ", target, "] Error ", code)
                if (!("k" %in% options)) abort_build()
                return("failure")
            }
        }
        "success"
    }
    make <- function(args) {
        options <- goals <- character()
        for (word in words(args)) {
            if (startsWith(word, "-")) {
                for (char in strsplit(part(word, 1), "", fixed = TRUE)[[1]]) {
                    if (!(char %in% c("n", "B", "k", "i", "s"))) {
                        emit("make: invalid option -- '", char, "'")
                        return(invisible(NULL))
                    }
                    options <- c(options, char)
                }
            } else {
                goals <- c(goals, word)
            }
        }
        if (length(goals) == 0) {
            if (!state$loaded) {
                emit("make: *** No targets specified and no makefile found.  Stop.")
                return(invisible(NULL))
            }
            if (is.null(state$default)) {
                emit("make: *** No targets.  Stop.")
                return(invisible(NULL))
            }
            goals <- state$default
        }
        saved_files <- state$files
        saved_clock <- state$clock
        on.exit({
            if ("n" %in% options) {
                state$files <- saved_files
                state$clock <- saved_clock
            }
            state$location <- "make"
            state$automatic <- NULL
        })
        results <- used <- building <- list()
        count <- 0
        build <- function(target, parent = NULL) {
            if (!is.null(results[[target]])) return(results[[target]])
            rule <- determine(target)
            used[[target]] <<- rule
            if (rule$kind == "missing") {
                results[[target]] <<- "failure"
                emit("make: *** No rule to make target '", target, "'", if (is.null(parent)) "" else paste0(", needed by '", parent, "'"), ".", if ("k" %in% options) "" else "  Stop.")
                if (!("k" %in% options)) abort_build()
                return("failure")
            }
            if (rule$kind == "source") {
                results[[target]] <<- "success"
                return("success")
            }
            building[[target]] <<- TRUE
            failed <- FALSE
            kept <- character()
            for (p in rule$prerequisites) {
                if (!is.null(building[[p]])) {
                    emit("make: Circular ", target, " <- ", p, " dependency dropped.")
                } else {
                    kept <- c(kept, p)
                    if (build(p, target) != "success") failed <- TRUE
                }
            }
            building[[target]] <<- NULL
            if (failed) {
                result <- "dependency_failure"
            } else {
                time <- target_time(target)
                newer <- kept[vapply(kept, function(p) "B" %in% options || is.null(time) || is.null(target_time(p)) || target_time(p) > time, logical(1))]
                if (is.null(rule$recipe) || (!("B" %in% options) && !is.null(time) && length(newer) == 0)) {
                    result <- "success"
                } else {
                    count <<- count + 1
                    result <- run_recipe(target, kept, rule$recipe, rule$stem, newer, options)
                    if (result == "success" && !(target %in% state$phony)) new_time(target)
                }
            }
            results[[target]] <<- result
            result
        }
        tryCatch({
            for (goal in goals) {
                before <- count
                result <- build(goal)
                if (result == "success" && count == before) {
                    emit(if (goal %in% state$phony || is.null(used[[goal]]$recipe)) paste0("make: Nothing to be done for '", goal, "'.") else paste0("make: '", goal, "' is up to date."))
                } else if (result == "dependency_failure") {
                    emit("make: Target '", goal, "' not remade because of errors.")
                }
            }
        }, build_abort = function(error) NULL, make_error = report)
        invisible(NULL)
    }
    execute <- function(line, body) {
        emit("$ ", line)
        space <- regexpr(" ", line, fixed = TRUE)[1]
        command <- if (space < 0) line else part(line, 0, space - 1L)
        args <- if (space < 0) "" else part(line, space)
        if (command == "MAKEFILE") {
            load_makefile(body)
        } else if (command == "MAKE") {
            make(args)
        } else if (command == "TOUCH") {
            for (name in words(args)) new_time(name)
        } else if (command == "RM") {
            for (name in words(args)) remove_file(name)
        } else if (command == "FILES") {
            emit("clock ", state$clock)
            for (name in ascii_sort(names(state$files))) emit(name, " ", state$files[[name]])
        } else if (command == "VARS" && state$loaded) {
            for (name in ascii_sort(names(state$variables))) {
                value <- trim(variable_value(name))
                emit(name, " ", state$variables[[name]]$kind, if (nzchar(value)) paste0(" ", value) else "")
            }
        } else if (command == "RULES" && state$loaded) {
            rules <- c(state$rules[ascii_sort(names(state$rules))], Filter(function(rule) !is.null(rule$recipe), state$patterns))
            for (rule in rules) {
                emit(rule$target, ":", if (length(rule$prerequisites) == 0) "" else paste0(" ", paste(rule$prerequisites, collapse = " ")))
                if (!is.null(rule$recipe)) for (line in rule$recipe$lines) emit(">", line$text)
            }
            if (length(state$phony) > 0) emit(".PHONY: ", paste(ascii_sort(state$phony), collapse = " "))
        } else if (command == "EXPAND") {
            result <- expand(args)
            emit("[", result, "]")
        }
        invisible(NULL)
    }
    function(line, body = NULL) tryCatch(execute(line, body), make_error = report)
}

input <- readLines(file("stdin"), warn = FALSE)
i <- 2L
files <- list()
while (input[i] != "END FILES") {
    entry <- strsplit(input[i], " ", fixed = TRUE)[[1]]
    files[[entry[1]]] <- as.integer(entry[2])
    i <- i + 1L
}
i <- i + 1L
workbench <- make_workbench(files)
while (input[i] != "QUIT") {
    line <- input[i]
    i <- i + 1L
    body <- NULL
    if (line == "MAKEFILE") {
        body <- character()
        while (input[i] != "END MAKEFILE") {
            body <- c(body, input[i])
            i <- i + 1L
        }
        i <- i + 1L
    }
    workbench(line, body)
}
