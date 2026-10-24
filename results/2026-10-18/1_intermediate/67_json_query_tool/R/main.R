value <- function(kind = "null", data = NULL) list2env(list(kind = kind, data = data), parent = emptyenv())
copy_value <- function(v) unserialize(serialize(v, NULL))
emit <- function(...) cat(paste0(...), "\n", sep = "")
fail <- function(message) stop(structure(list(message = message, call = NULL), class = c("command_error", "error", "condition")))
parse_fail <- function(message, position) stop(structure(list(message = message, position = position, call = NULL), class = c("parse_error", "error", "condition")))
slice <- function(text, first, last = nchar(text)) if (first > last) "" else substr(text, first, last)
letters_of <- function(text) strsplit(text, "", fixed = TRUE)[[1]]
quoted <- function(text, quote = '"') {
    escapes <- c("8" = "\\b", "12" = "\\f", "10" = "\\n", "13" = "\\r", "9" = "\\t")
    encoded <- vapply(letters_of(text), function(char) {
        number <- utf8ToInt(char)
        if (char == quote || char == "\\") return(paste0("\\", char))
        if (as.character(number) %in% names(escapes)) return(escapes[[as.character(number)]])
        if (number < 32 || number == 127) return(sprintf("\\u%04x", number))
        char
    }, character(1))
    paste0(quote, paste(encoded, collapse = ""), quote)
}
member <- function(v, key) {
    if (v$kind == "object") for (i in seq_along(v$data)) if (v$data[[i]][[1]] == key) return(i)
    0L
}
compact <- function(v) {
    switch(v$kind, "null" = "null", number = sprintf("%.0f", v$data), boolean = if (v$data) "true" else "false", string = quoted(v$data),
           array = paste0("[", paste(vapply(v$data, compact, character(1)), collapse = ","), "]"),
           object = paste0("{", paste(vapply(v$data, function(pair) paste0(quoted(pair[[1]]), ":", compact(pair[[2]])), character(1)), collapse = ","), "}"))
}
pretty <- function(v, indent = "") {
    if (!(v$kind %in% c("object", "array")) || !length(v$data)) return(compact(v))
    next_indent <- paste0(indent, "  ")
    items <- if (v$kind == "object") vapply(v$data, function(pair) paste0(next_indent, quoted(pair[[1]]), ": ", pretty(pair[[2]], next_indent)), character(1)) else vapply(v$data, function(item) paste0(next_indent, pretty(item, next_indent)), character(1))
    paste0(if (v$kind == "object") "{" else "[", "\n", paste(items, collapse = ",\n"), "\n", indent, if (v$kind == "object") "}" else "]")
}
read_json <- function(text) {
    position <- 1
    char <- function() slice(text, position, position)
    whitespace <- function() while (char() %in% c(" ", "\n")) position <<- position + 1
    error <- function(reason, at = position) parse_fail(reason, at)
    read_string <- function() {
        position <<- position + 1
        output <- ""
        repeat {
            c <- char()
            if (c == "" || c == "\n") error("unterminated string")
            if (c == '"') {
                position <<- position + 1
                return(output)
            }
            if (c == "\\") {
                start <- position
                escaped <- slice(text, position + 1, position + 1)
                if (escaped == "" || escaped == "\n") error("unterminated string", start + 1)
                if (escaped == "u") {
                    hex <- slice(text, position + 2, position + 5)
                    if (!grepl("^[0-9A-Fa-f]{4}$", hex)) error("bad unicode escape", start)
                    if (strtoi(hex, 16) > 127) error("non-ascii escape", start)
                    output <- paste0(output, intToUtf8(strtoi(hex, 16)))
                    position <<- position + 6
                } else {
                    escapes <- c('"' = '"', "\\" = "\\", "/" = "/", "b" = "\b", "f" = "\f", "n" = "\n", "r" = "\r", "t" = "\t")
                    if (!(escaped %in% names(escapes))) error(paste0("invalid escape '\\", escaped, "'"), start)
                    output <- paste0(output, escapes[[escaped]])
                    position <<- position + 2
                }
            } else {
                output <- paste0(output, c)
                position <<- position + 1
            }
        }
    }
    read_value <- function() {
        whitespace()
        c <- char()
        if (c == "") error("unexpected end of input")
        if (c %in% c("{", "[")) {
            object <- c == "{"
            ending <- if (object) "}" else "]"
            result <- value(if (object) "object" else "array", list())
            position <<- position + 1
            whitespace()
            if (char() == ending) {
                position <<- position + 1
                return(result)
            }
            repeat {
                if (object) {
                    whitespace()
                    if (char() == "") error("unexpected end of input")
                    if (char() != '"') error("expected key")
                    start <- position
                    key <- read_string()
                    if (member(result, key)) error(paste0("duplicate key ", quoted(key)), start)
                    whitespace()
                    if (char() == "") error("unexpected end of input")
                    if (char() != ":") error("expected ':'")
                    position <<- position + 1
                    result$data[[length(result$data) + 1]] <- list(key, read_value())
                } else result$data[[length(result$data) + 1]] <- read_value()
                whitespace()
                if (char() == ending) {
                    position <<- position + 1
                    return(result)
                }
                if (char() == "") error("unexpected end of input")
                if (char() != ",") error(paste0("expected ',' or '", ending, "'"))
                position <<- position + 1
                whitespace()
                if (char() == ending) error("trailing comma")
            }
        }
        if (c == '"') return(value("string", read_string()))
        if (c == "-" || grepl("^[0-9]$", c)) {
            start <- position
            if (c == "-") position <<- position + 1
            digit_start <- position
            while (grepl("^[0-9]$", char())) position <<- position + 1
            digits <- slice(text, digit_start, position - 1)
            if (digits == "") error("invalid number", start)
            if (nchar(digits) > 1 && startsWith(digits, "0")) error("leading zero", digit_start)
            if (char() == ".") error("fraction not allowed")
            if (char() %in% c("e", "E")) error("exponent not allowed")
            if (nchar(digits) >= 10) error("number out of range", start)
            return(value("number", as.numeric(slice(text, start, position - 1))))
        }
        if (grepl("^[A-Za-z]$", c)) {
            start <- position
            while (grepl("^[A-Za-z]$", char())) position <<- position + 1
            word <- slice(text, start, position - 1)
            if (!(word %in% c("true", "false", "null"))) error(paste0("invalid literal '", word, "'"), start)
            return(if (word == "null") value() else value("boolean", word == "true"))
        }
        error(paste0("unexpected character '", c, "'"))
    }
    result <- read_value()
    whitespace()
    if (position <= nchar(text)) error("trailing characters")
    result
}
integer_pattern <- "^(0|-?[1-9][0-9]{0,8})$"
identifier <- "\\A[A-Za-z_][A-Za-z0-9_]*\\z"
quoted_key <- function(text, position) {
    if (slice(text, position, position) != "'") stop("bad")
    position <- position + 1
    output <- ""
    while (position <= nchar(text)) {
        char <- substr(text, position, position)
        if (char == "'") return(list(text = output, position = position + 1))
        if (char == "\\") {
            escaped <- slice(text, position + 1, position + 1)
            if (escaped == "u") {
                hex <- slice(text, position + 2, position + 5)
                if (!grepl("^[0-9A-Fa-f]{4}$", hex) || strtoi(hex, 16) > 127) stop("bad")
                output <- paste0(output, intToUtf8(strtoi(hex, 16)))
                position <- position + 6
            } else {
                escapes <- c("'" = "'", "\\" = "\\", "/" = "/", "b" = "\b", "f" = "\f", "n" = "\n", "r" = "\r", "t" = "\t")
                if (!(escaped %in% names(escapes))) stop("bad")
                output <- paste0(output, escapes[[escaped]])
                position <- position + 2
            }
        } else {
            output <- paste0(output, char)
            position <- position + 1
        }
    }
    stop("bad")
}
parse_path <- function(text, field = FALSE) {
    tryCatch({
        if (slice(text, 1, 1) != if (field) "@" else "$") stop("bad")
        position <- 2
        selectors <- list()
        word <- function() {
            rest <- slice(text, position)
            match <- regexpr("^([A-Za-z_][A-Za-z0-9_]*|\\*)", rest)
            if (match[1] < 0) stop("bad")
            regmatches(rest, match)
        }
        while (position <= nchar(text)) {
            descendant <- FALSE
            if (!field && slice(text, position, position + 1) == "..") {
                descendant <- TRUE
                position <- position + 2
            } else if (substr(text, position, position) == ".") {
                position <- position + 1
                key <- word()
                if (field && key == "*") stop("bad")
                selectors[[length(selectors) + 1]] <- list(descendant = FALSE, kind = if (key == "*") "all" else "key", key = key)
                position <- position + nchar(key)
                next
            } else if (substr(text, position, position) != "[") stop("bad")
            if (slice(text, position, position) == "[") {
                position <- position + 1
                if (slice(text, position, position) == "'") {
                    parsed <- quoted_key(text, position)
                    key <- parsed$text
                    position <- parsed$position
                    kind <- "key"
                } else {
                    at <- regexpr("]", slice(text, position), fixed = TRUE)[1]
                    if (at < 0) stop("bad")
                    finish <- position + at - 1
                    token <- slice(text, position, finish - 1)
                    position <- finish
                    if (grepl(integer_pattern, token)) {
                        kind <- "index"
                        key <- as.numeric(token)
                    } else if (!field && token == "*") {
                        kind <- "all"
                        key <- NULL
                    } else if (!field && sum(letters_of(token) == ":") == 1) {
                        at <- regexpr(":", token, fixed = TRUE)[1]
                        bounds <- c(slice(token, 1, at - 1), slice(token, at + 1))
                        if (any(bounds != "" & !grepl(integer_pattern, bounds))) stop("bad")
                        kind <- "slice"
                        key <- lapply(bounds, function(bound) if (bound == "") NULL else as.numeric(bound))
                    } else stop("bad")
                }
                if (slice(text, position, position) != "]") stop("bad")
                position <- position + 1
            } else if (descendant) {
                key <- word()
                kind <- if (key == "*") "all" else "key"
                position <- position + nchar(key)
            } else stop("bad")
            selectors[[length(selectors) + 1]] <- list(descendant = descendant, kind = kind, key = key)
        }
        selectors
    }, error = function(e) fail(if (field) "ERROR bad field" else "ERROR bad path"))
}
location <- function(steps) {
    paste0("$", paste(vapply(steps, function(step) if (is.numeric(step)) paste0("[", step, "]") else if (grepl(identifier, step, perl = TRUE)) paste0(".", step) else paste0("[", quoted(step, "'"), "]"), character(1)), collapse = ""))
}
children <- function(match) {
    v <- match$value
    output <- list()
    if (v$kind == "object") {
        for (i in seq_along(v$data)) output[[length(output) + 1]] <- list(value = v$data[[i]][[2]], steps = c(match$steps, list(v$data[[i]][[1]])), positions = c(match$positions, i - 1L))
    } else if (v$kind == "array") {
        for (i in seq_along(v$data)) output[[length(output) + 1]] <- list(value = v$data[[i]], steps = c(match$steps, list(i - 1L)), positions = c(match$positions, i - 1L))
    }
    output
}
preorder <- function(match) c(list(match), unlist(lapply(children(match), preorder), recursive = FALSE))
select <- function(match, selector) {
    v <- match$value
    all <- children(match)
    kind <- selector$kind
    key <- selector$key
    if (kind == "all") return(all)
    if (kind == "key") return(if (v$kind == "object") Filter(function(item) identical(tail(item$steps, 1)[[1]], key), all) else list())
    if (v$kind != "array") return(list())
    n <- length(v$data)
    if (kind == "index") {
        index <- if (key < 0) n + key else key
        return(if (index >= 0 && index < n) list(all[[index + 1]]) else list())
    }
    bounds <- c(if (is.null(key[[1]])) 0 else key[[1]], if (is.null(key[[2]])) n else key[[2]])
    bounds <- pmin(n, pmax(0, ifelse(bounds < 0, bounds + n, bounds)))
    if (bounds[1] < bounds[2]) all[seq.int(bounds[1] + 1, bounds[2])] else list()
}
document <- value()
history <- list()
evaluate <- function(selectors, initial = list(list(value = document, steps = list(), positions = integer()))) {
    matches <- initial
    for (selector in selectors) {
        next_matches <- list()
        for (match in matches) for (item in if (selector$descendant) preorder(match) else list(match)) next_matches <- c(next_matches, select(item, selector))
        matches <- next_matches
    }
    matches
}
field_value <- function(v, selectors) {
    matches <- evaluate(selectors, list(list(value = v, steps = list(), positions = integer())))
    if (length(matches)) matches[[1]]$value else NULL
}
at <- function(steps) {
    v <- document
    for (step in steps) v <- if (is.numeric(step)) v$data[[step + 1]] else v$data[[member(v, step)]][[2]]
    v
}
assign_value <- function(steps, v) {
    if (!length(steps)) {
        document <<- v
        return(invisible(NULL))
    }
    last <- tail(steps, 1)[[1]]
    parent <- at(head(steps, -1))
    if (is.numeric(last)) parent$data[[last + 1]] <- v else {
        index <- member(parent, last)
        if (index) parent$data[[index]][[2]] <- v else parent$data[[length(parent$data) + 1]] <- list(last, v)
    }
}
merge_value <- function(target, source) {
    for (pair in source$data) {
        key <- pair[[1]]
        child <- pair[[2]]
        index <- member(target, key)
        if (index && target$data[[index]][[2]]$kind == "object" && child$kind == "object") merge_value(target$data[[index]][[2]], child)
        else if (index) target$data[[index]][[2]] <- copy_value(child)
        else target$data[[length(target$data) + 1]] <- list(key, copy_value(child))
    }
}
equal_value <- function(left, right) {
    if (is.null(left) || left$kind != right$kind) return(FALSE)
    if (left$kind == "object") {
        if (length(left$data) != length(right$data)) return(FALSE)
        for (pair in left$data) {
            index <- member(right, pair[[1]])
            if (!index || !equal_value(pair[[2]], right$data[[index]][[2]])) return(FALSE)
        }
        return(TRUE)
    }
    if (left$kind == "array") {
        if (length(left$data) != length(right$data)) return(FALSE)
        return(all(vapply(seq_along(left$data), function(i) equal_value(left$data[[i]], right$data[[i]]), logical(1))))
    }
    identical(left$data, right$data)
}
check_kinds <- function(matches, kinds, reason) {
    for (match in matches) if (!(match$value$kind %in% kinds)) fail(paste0("ERROR ", reason, " at ", location(match$steps)))
}
parse_argument <- function(text) tryCatch(read_json(text), parse_error = function(e) fail(paste0("PARSE ERROR col ", e$position, ": ", e$message)))
split_arguments <- function(text, limit = Inf) {
    if (is.null(text)) return(character())
    parts <- character()
    while (length(parts) < limit - 1) {
        at <- regexpr(" ", text, fixed = TRUE)[1]
        if (at < 0) break
        parts <- c(parts, slice(text, 1, at - 1))
        text <- slice(text, at + 1)
    }
    c(parts, text)
}
command <- function(line) {
    at_space <- regexpr(" ", line, fixed = TRUE)[1]
    name <- if (at_space < 0) line else slice(line, 1, at_space - 1)
    argument <- if (at_space < 0) NULL else slice(line, at_space + 1)
    tryCatch({
        names <- c("GET", "COMPACT", "PRETTY", "TYPE", "LENGTH", "KEYS", "FLATTEN", "COUNT", "SUM", "MIN", "MAX", "AVG", "FILTER", "SET", "DELETE", "INSERT", "MERGE", "SORT", "RENAME", "UNDO")
        if (!(name %in% names)) fail(paste0("ERROR unknown command '", name, "'"))
        limit <- switch(name, SET = 2, MERGE = 2, INSERT = 3, FILTER = 4, Inf)
        args <- split_arguments(argument, limit)
        count <- length(args)
        shape <- switch(name, SET = count == 2, MERGE = count == 2, INSERT = count == 3,
                        FILTER = count >= 3 && if (args[3] == "EXISTS") count == 3 else count == 4,
                        SORT = count >= 1 && count <= 3 && (count < 3 || (args[2] != "DESC" && args[3] == "DESC")),
                        COMPACT = count <= 1, PRETTY = count <= 1, FLATTEN = count <= 1, UNDO = count == 0, RENAME = count == 2, count == 1)
        if (!shape) fail("ERROR bad arguments")
        if (name == "UNDO") {
            if (!length(history)) fail("ERROR nothing to undo")
            document <<- history[[length(history)]]
            history <<- head(history, -1)
            emit("UNDO ", length(history))
            return(invisible(NULL))
        }
        selectors <- parse_path(if (count) args[1] else "$")
        field <- list()
        if (name == "FILTER") {
            field <- parse_path(args[2], TRUE)
            if (!(args[3] %in% c("==", "!=", "<", "<=", ">", ">=", "EXISTS"))) fail("ERROR bad operator")
        } else if (name == "SORT") field <- parse_path(if (count >= 2 && args[2] != "DESC") args[2] else "@", TRUE)
        else if (name == "INSERT" && !grepl(integer_pattern, args[2])) fail("ERROR bad index")
        else if (name == "RENAME") {
            new_key <- tryCatch({
                if (grepl(identifier, args[2], perl = TRUE)) args[2] else {
                    parsed <- quoted_key(args[2], 1)
                    if (parsed$position != nchar(args[2]) + 1) stop("bad")
                    parsed$text
                }
            }, error = function(e) fail("ERROR bad key"))
        } else if (name == "DELETE" && !length(selectors)) fail("ERROR cannot delete root")
        replacement <- value()
        if (name %in% c("SET", "MERGE", "INSERT") || (name == "FILTER" && args[3] != "EXISTS")) replacement <- parse_argument(tail(args, 1))
        if (name == "MERGE" && replacement$kind != "object") fail("ERROR merge value is not an object")
        matches <- evaluate(selectors)
        if (name == "LENGTH") check_kinds(matches, c("object", "array", "string"), "no length")
        if (name %in% c("KEYS", "MERGE")) check_kinds(matches, "object", "not an object")
        if (name %in% c("FILTER", "INSERT", "SORT")) check_kinds(matches, "array", "not an array")
        if (name == "RENAME") for (match in matches) if (!length(match$steps) || !is.character(tail(match$steps, 1)[[1]])) fail(paste0("ERROR not a member at ", location(match$steps)))
        if (name == "INSERT") {
            index <- as.numeric(args[2])
            for (match in matches) if (index < -length(match$value$data) - 1 || index > length(match$value$data)) fail(paste0("ERROR index out of range at ", location(match$steps)))
        }
        if (name %in% c("SET", "DELETE", "INSERT", "MERGE", "SORT", "RENAME")) {
            if (name == "SET" && length(selectors) && !tail(selectors, 1)[[1]]$descendant && tail(selectors, 1)[[1]]$kind == "key") {
                key <- tail(selectors, 1)[[1]]$key
                matches <- list()
                for (parent in evaluate(head(selectors, -1))) {
                    if (parent$value$kind != "object") next
                    index <- member(parent$value, key)
                    matches[[length(matches) + 1]] <- list(value = NULL, steps = c(parent$steps, list(key)), positions = c(parent$positions, if (index) index - 1 else length(parent$value$data)))
                }
            }
            keys <- vapply(matches, function(match) location(match$steps), character(1))
            targets <- matches[!duplicated(keys)]
            ordering_keys <- vapply(targets, function(match) paste(sprintf("%010d", match$positions), collapse = "/"), character(1))
            targets <- targets[order(ordering_keys, decreasing = TRUE, method = "radix")]
            original <- copy_value(document)
            tryCatch({
                for (target in targets) {
                    steps <- target$steps
                    v <- if (name == "SET") NULL else at(steps)
                    if (name == "SET") assign_value(steps, copy_value(replacement))
                    else if (name == "DELETE") {
                        last <- tail(steps, 1)[[1]]
                        parent <- at(head(steps, -1))
                        index <- if (is.numeric(last)) last + 1 else member(parent, last)
                        parent$data <- parent$data[-index]
                    } else if (name == "INSERT") {
                        j <- if (index < 0) length(v$data) + 1 + index else index
                        v$data <- append(v$data, list(copy_value(replacement)), after = j)
                    } else if (name == "MERGE") merge_value(v, replacement)
                    else if (name == "SORT") {
                        sort_keys <- lapply(v$data, field_value, selectors = field)
                        ranks <- vapply(sort_keys, function(k) if (is.null(k)) 3 else switch(k$kind, "null" = 0, number = 1, string = 2, 3), numeric(1))
                        numbers <- vapply(sort_keys, function(k) if (!is.null(k) && k$kind == "number") k$data else 0, numeric(1))
                        strings <- vapply(sort_keys, function(k) if (!is.null(k) && k$kind == "string") k$data else "", character(1))
                        descending <- tail(args, 1) == "DESC"
                        indices <- order(ranks, numbers, strings, decreasing = descending, method = "radix")
                        v$data <- v$data[indices]
                    } else if (name == "RENAME") {
                        last <- tail(steps, 1)[[1]]
                        parent <- at(head(steps, -1))
                        if (last != new_key && member(parent, new_key)) fail(paste0("ERROR key exists at ", location(steps)))
                        parent$data[[member(parent, last)]][[1]] <- new_key
                    }
                }
            }, command_error = function(e) {
                document <<- original
                stop(e)
            })
            history[[length(history) + 1]] <<- original
            emit(name, " ", length(targets))
            return(invisible(NULL))
        }
        if (name %in% c("COUNT", "SUM", "MIN", "MAX", "AVG")) {
            numbers <- vapply(Filter(function(match) match$value$kind == "number", matches), function(match) match$value$data, numeric(1))
            result <- if (name == "COUNT") as.character(length(matches)) else if (name == "SUM") sprintf("%.0f", sum(numbers)) else if (!length(numbers)) "null" else if (name == "MIN") sprintf("%.0f", min(numbers)) else if (name == "MAX") sprintf("%.0f", max(numbers)) else {
                sum <- sum(numbers)
                rounded <- floor((abs(sum) * 200 + length(numbers)) / (2 * length(numbers)))
                sprintf("%s%.0f.%02d", if (sum < 0 && rounded > 0) "-" else "", floor(rounded / 100), as.integer(rounded %% 100))
            }
            emit(name, " ", result)
            return(invisible(NULL))
        }
        output <- character()
        for (match in matches) {
            v <- match$value
            where <- location(match$steps)
            if (name == "GET") output <- c(output, paste0(where, " = ", compact(v)))
            else if (name == "COMPACT") output <- c(output, compact(v))
            else if (name == "PRETTY") output <- c(output, pretty(v))
            else if (name == "TYPE") output <- c(output, paste0(where, " ", v$kind))
            else if (name == "LENGTH") output <- c(output, paste0(where, " ", if (v$kind == "string") nchar(v$data) else length(v$data)))
            else if (name == "KEYS") output <- c(output, paste0(where, " [", paste(vapply(v$data, function(pair) quoted(pair[[1]]), character(1)), collapse = ","), "]"))
            else if (name == "FLATTEN") {
                for (item in preorder(match)) if (!length(children(item))) output <- c(output, paste0(location(item$steps), " = ", compact(item$value)))
            } else if (name == "FILTER") {
                for (item in children(match)) {
                    f <- field_value(item$value, field)
                    operator <- args[3]
                    equal <- equal_value(f, replacement)
                    pass <- if (operator == "EXISTS") !is.null(f) else if (operator == "==") equal else if (operator == "!=") !equal else if (!is.null(f) && f$kind == replacement$kind && f$kind %in% c("number", "string")) {
                        if (f$kind == "number") comparison <- sign(f$data - replacement$data) else {
                            ordering <- order(c(f$data, replacement$data), method = "radix")
                            comparison <- if (f$data == replacement$data) 0 else if (ordering[1] == 1) -1 else 1
                        }
                        switch(operator, "<" = comparison < 0, "<=" = comparison <= 0, ">" = comparison > 0, ">=" = comparison >= 0)
                    } else FALSE
                    if (pass) output <- c(output, paste0(location(item$steps), " = ", compact(item$value)))
                }
            }
        }
        if (length(output)) cat(paste0(output, "\n"), sep = "") else emit("no match")
    }, command_error = function(e) emit(e$message))
}
load_document <- function(lines) {
    text <- paste(lines, collapse = "\n")
    tryCatch({
        v <- read_json(text)
        history[[length(history) + 1]] <<- copy_value(document)
        document <<- v
        stats <- function(v) {
            nested <- if (v$kind == "object") lapply(v$data, function(pair) stats(pair[[2]])) else if (v$kind == "array") lapply(v$data, stats) else list()
            c(1 + sum(vapply(nested, function(item) item[1], numeric(1))), 1 + max(c(0, vapply(nested, function(item) item[2], numeric(1)))))
        }
        numbers <- stats(v)
        emit("LOADED nodes=", numbers[1], " depth=", numbers[2])
    }, parse_error = function(e) {
        prefix <- slice(text, 1, e$position - 1)
        line <- sum(letters_of(prefix) == "\n") + 1
        breaks <- which(letters_of(prefix) == "\n")
        column <- e$position - if (length(breaks)) tail(breaks, 1) else 0
        emit("PARSE ERROR line ", line, " col ", column, ": ", e$message)
    })
}
input <- readLines(file("stdin"), warn = FALSE)
position <- 1
repeat {
    block <- character()
    while (input[position] != "%%") {
        block <- c(block, input[position])
        position <- position + 1
    }
    position <- position + 1
    load_document(block)
    while (!(input[position] %in% c("LOAD", "END"))) {
        command(input[position])
        position <- position + 1
    }
    if (input[position] == "END") break
    position <- position + 1
}
