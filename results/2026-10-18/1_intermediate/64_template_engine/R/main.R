value <- function(kind, data = NULL) list(kind = kind, data = data)
absent <- value("absent")
root <- value("map", list())
partials <- list()
templates <- list()
strict <- FALSE
identifier <- "^[A-Za-z_][A-Za-z0-9_]*$"
name_pattern <- "^(\\.|@(index|number|first|last)|([A-Za-z_][A-Za-z0-9_]*|0|[1-9][0-9]*)(\\.([A-Za-z_][A-Za-z0-9_]*|0|[1-9][0-9]*))*)$"
no_arguments <- c("upper", "lower", "title", "trim", "length", "first", "last", "reverse", "items", "comma", "sum", "min", "max")
all_filters <- c(no_arguments, "default", "eq", "pad", "lpad", "truncate", "replace", "join", "sort", "pluck", "add", "sub", "mul", "div", "mod", "gt", "lt")
strip_spaces <- function(text) {
    first <- 1
    last <- nchar(text)
    while (first <= last && substr(text, first, first) == " ") first <- first + 1
    while (last >= first && substr(text, last, last) == " ") last <- last - 1
    if (first > last) "" else substr(text, first, last)
}
fail <- function(message, line = NULL) {
    stop(structure(list(message = message, call = NULL, line = line), class = c("template_error", "error", "condition")))
}
chars <- function(text) strsplit(text, "", fixed = TRUE)[[1]]
text_slice <- function(text, start, end = nchar(text)) {
    if (start > end) "" else substr(text, start, end)
}
key_parts <- function(key) {
    pattern <- "^[A-Za-z_][A-Za-z0-9_]*((\\.[A-Za-z_][A-Za-z0-9_]*)|(\\[(0|[1-9][0-9]*)\\]))*$"
    if (!grepl(pattern, key)) return(NULL)
    matches <- gregexpr("[A-Za-z_][A-Za-z0-9_]*|\\[(0|[1-9][0-9]*)\\]", key, perl = TRUE)[[1]]
    lengths <- attr(matches, "match.length")
    lapply(seq_along(matches), function(i) {
        part <- substr(key, matches[i], matches[i] + lengths[i] - 1)
        index <- startsWith(part, "[")
        list(part = if (index) as.numeric(substr(part, 2, nchar(part) - 1)) else part,
             prefix = substr(key, 1, matches[i] + lengths[i] - 1))
    })
}
parse_scalar <- function(text, position) {
    if (text_slice(text, position, position) == '"') {
        position <- position + 1
        output <- ""
        while (position <= nchar(text)) {
            char <- substr(text, position, position)
            position <- position + 1
            if (char == '"') return(list(value = value("string", output), position = position))
            if (char == "\\") {
                char <- text_slice(text, position, position)
                position <- position + 1
                if (!(char %in% c('"', "\\", "n"))) stop("bad value")
                if (char == "n") char <- "\n"
            }
            output <- paste0(output, char)
        }
        stop("bad value")
    }
    rest <- text_slice(text, position)
    match <- regexpr("^(0|-?[1-9][0-9]*|true|false)", rest, perl = TRUE)
    if (match[1] < 0) stop("bad value")
    word <- regmatches(rest, match)
    parsed <- if (word %in% c("true", "false")) value("boolean", word == "true") else value("integer", as.numeric(word))
    list(value = parsed, position = position + nchar(word))
}
parse_value <- function(text) {
    if (text == "[]") return(value("list", list()))
    if (text == "{}") return(value("map", list()))
    if (startsWith(text, "[")) {
        output <- list()
        position <- 2
        repeat {
            parsed <- parse_scalar(text, position)
            output[[length(output) + 1]] <- parsed$value
            position <- parsed$position
            if (text_slice(text, position, position) == "]" && position == nchar(text)) return(value("list", output))
            if (text_slice(text, position, position + 1) != ", ") stop("bad value")
            position <- position + 2
        }
    }
    parsed <- parse_scalar(text, 1)
    if (parsed$position != nchar(text) + 1) stop("bad value")
    parsed$value
}
has_part <- function(v, part) {
    if (is.character(part)) return(v$kind == "map" && part %in% names(v$data))
    v$kind == "list" && part >= 0 && part < length(v$data)
}
get_part <- function(v, part) {
    if (is.character(part)) v$data[[part]] else v$data[[part + 1]]
}
put_part <- function(v, part, child) {
    if (is.character(part)) v$data[part] <- list(child) else v$data[part + 1] <- list(child)
    v
}
assign_value <- function(container, parts, new_value, index = 1) {
    part <- parts[[index]]$part
    prefix <- parts[[index]]$prefix
    if (is.numeric(part) && part > length(container$data)) fail(paste0("index gap at '", prefix, "'"))
    if (index == length(parts)) return(put_part(container, part, new_value))
    kind <- if (is.numeric(parts[[index + 1]]$part)) "list" else "map"
    if (has_part(container, part)) {
        child <- get_part(container, part)
        if (child$kind != kind) fail(paste0("type conflict at '", prefix, "'"))
    } else {
        child <- value(kind, list())
    }
    put_part(container, part, assign_value(child, parts, new_value, index + 1))
}
unset_value <- function(container, parts, key, index = 1) {
    part <- parts[[index]]$part
    if (!has_part(container, part)) fail(paste0("no value at '", key, "'"))
    if (index == length(parts)) {
        if (is.character(part)) container$data[part] <- NULL else container$data[part + 1] <- NULL
        return(container)
    }
    put_part(container, part, unset_value(get_part(container, part), parts, key, index + 1))
}
data_block <- function(body) {
    sets <- 0
    unsets <- 0
    errors <- character()
    for (entry in body) {
        text <- entry$text
        if (text == "" || startsWith(text, "#")) next
        tryCatch({
            deleting <- startsWith(text, "UNSET ")
            if (deleting) {
                key <- substring(text, 7)
            } else {
                at <- regexpr(" = ", text, fixed = TRUE)[1]
                if (at < 0) fail("bad line")
                key <- text_slice(text, 1, at - 1)
                notation <- text_slice(text, at + 3)
            }
            parts <- key_parts(key)
            if (is.null(parts)) fail(paste0("bad key '", key, "'"))
            if (!deleting) {
                parsed <- tryCatch(parse_value(notation), error = function(e) NULL)
                if (is.null(parsed)) fail(paste0("bad value '", notation, "'"))
            }
            if (deleting) {
                root <<- unset_value(root, parts, key)
                unsets <- unsets + 1
            } else {
                root <<- assign_value(root, parts, parsed)
                sets <- sets + 1
            }
        }, template_error = function(e) {
            errors <<- c(errors, paste0("ERROR line ", entry$line, ": ", e$message))
        })
    }
    cat(sprintf("DATA set=%d unset=%d errors=%d\n", sets, unsets, length(errors)))
    if (length(errors)) cat(paste0(errors, "\n"), sep = "")
}
split_quoted <- function(text, separator) {
    output <- character()
    quoted <- FALSE
    start <- 1
    letters <- chars(text)
    for (i in seq_along(letters)) {
        if (letters[i] == "'") quoted <- !quoted
        if (letters[i] == separator && !quoted) {
            output <- c(output, text_slice(text, start, i - 1))
            start <- i + 1
        }
    }
    c(output, text_slice(text, start))
}
parse_expression <- function(text, line) {
    pieces <- vapply(split_quoted(text, "|"), strip_spaces, character(1))
    name <- pieces[1]
    if (!grepl(name_pattern, name)) fail(paste0("invalid name '", name, "'"), line)
    filters <- list()
    for (piece in pieces[-1]) {
        parts <- split_quoted(piece, ":")
        filter <- parts[1]
        if (!(filter %in% all_filters)) fail(paste0("unknown filter '", filter, "'"), line)
        valid <- TRUE
        args <- lapply(parts[-1], function(argument) {
            if (grepl("^'[^']*'$", argument)) return(value("string", text_slice(argument, 2, nchar(argument) - 1)))
            if (grepl("^-?[0-9]{1,9}$", argument)) return(value("integer", as.numeric(argument)))
            valid <<- FALSE
            absent
        })
        count <- length(args)
        integers <- all(vapply(args, function(a) a$kind == "integer", logical(1)))
        strings <- all(vapply(args, function(a) a$kind == "string", logical(1)))
        correct <- if (filter %in% no_arguments) {
            count == 0
        } else if (filter %in% c("default", "eq")) {
            count == 1
        } else if (filter %in% c("pad", "lpad")) {
            count %in% c(1, 2) && args[[1]]$kind == "integer" && args[[1]]$data >= 0 &&
                (count == 1 || (args[[2]]$kind == "string" && nchar(args[[2]]$data) == 1))
        } else if (filter == "truncate") {
            count == 1 && integers && args[[1]]$data >= 0
        } else if (filter == "replace") {
            count == 2 && strings && args[[1]]$data != ""
        } else if (filter %in% c("join", "pluck")) {
            count == 1 && strings
        } else if (filter == "sort") {
            count <= 1 && strings
        } else {
            count == 1 && integers && (!(filter %in% c("div", "mod")) || args[[1]]$data != 0)
        }
        if (!valid || !correct) fail(paste0("bad arguments for '", filter, "'"), line)
        filters[[length(filters) + 1]] <- list(name = filter, args = args)
    }
    list(name = name, filters = filters)
}
find_from <- function(text, pattern, position) {
    match <- regexpr(pattern, text_slice(text, position), fixed = TRUE)[1]
    if (match < 0) -1 else match + position - 1
}
analyze <- function(body) {
    opening <- "{{"
    closing <- "}}"
    tokens <- list()
    sections <- list()
    kinds <- c("#" = "section", "^" = "inverted", "/" = "close", "!" = "comment", ">" = "partial", "&" = "raw", "=" = "delimiter")
    for (entry in body) {
        text <- entry$text
        line <- entry$line
        local <- list()
        position <- 1
        repeat {
            start <- find_from(text, opening, position)
            if (start < 0) {
                local[[length(local) + 1]] <- list(kind = "text", text = text_slice(text, position), line = line)
                break
            }
            local[[length(local) + 1]] <- list(kind = "text", text = text_slice(text, position, start - 1), line = line)
            content_start <- start + nchar(opening)
            triple <- text_slice(text, content_start, content_start) == "{"
            if (triple) content_start <- content_start + 1
            end_delimiter <- paste0(if (triple) "}" else "", closing)
            finish <- find_from(text, end_delimiter, content_start)
            if (finish < 0) fail("unclosed tag", line)
            content <- strip_spaces(text_slice(text, content_start, finish - 1))
            position <- finish + nchar(end_delimiter)
            marker <- text_slice(content, 1, 1)
            kind <- if (triple) "raw" else if (marker %in% names(kinds)) unname(kinds[marker]) else "variable"
            argument <- if (triple || kind == "variable") content else strip_spaces(text_slice(content, 2))
            token <- list(kind = kind, text = argument, line = line, indent = "")
            if (kind %in% c("variable", "raw", "section", "inverted")) {
                token$expression <- parse_expression(argument, line)
                if (kind %in% c("section", "inverted")) sections[[length(sections) + 1]] <- list(name = token$expression$name, line = line)
            } else if (kind == "close") {
                if (!grepl(name_pattern, argument)) fail(paste0("invalid name '", argument, "'"), line)
                if (!length(sections)) fail(paste0("unexpected closing '", argument, "'"), line)
                expected <- sections[[length(sections)]]$name
                if (expected != argument) fail(paste0("mismatched closing '", argument, "', expected '", expected, "'"), line)
                sections <- sections[-length(sections)]
            } else if (kind == "partial") {
                if (!grepl(identifier, argument)) fail(paste0("invalid name '", argument, "'"), line)
            } else if (kind == "delimiter") {
                delimiters <- character()
                if (nchar(content) >= 2 && endsWith(content, "=")) {
                    inner <- strip_spaces(text_slice(content, 2, nchar(content) - 1))
                    if (inner != "") delimiters <- strsplit(inner, " +")[[1]]
                }
                if (length(delimiters) != 2 || any(grepl("=", delimiters, fixed = TRUE))) fail("invalid delimiters", line)
                opening <- delimiters[1]
                closing <- delimiters[2]
            }
            local[[length(local) + 1]] <- token
        }
        tags <- Filter(function(t) t$kind != "text", local)
        standalone <- length(tags) == 1 && tags[[1]]$kind %in% c("section", "inverted", "close", "comment", "partial", "delimiter") &&
            all(vapply(local, function(t) t$kind != "text" || grepl("^ *$", t$text), logical(1)))
        if (standalone) {
            if (tags[[1]]$kind == "partial") tags[[1]]$indent <- local[[1]]$text
            tokens <- c(tokens, tags)
        } else {
            tokens <- c(tokens, local, list(list(kind = "text", text = "\n", line = line)))
        }
    }
    if (length(sections)) {
        section <- sections[[length(sections)]]
        fail(paste0("unclosed section '", section$name, "'"), section$line)
    }
    position <- 1
    tree <- function() {
        nodes <- list()
        while (position <= length(tokens)) {
            token <- tokens[[position]]
            position <<- position + 1
            if (token$kind == "close") break
            if (token$kind %in% c("section", "inverted")) token$children <- tree()
            nodes[[length(nodes) + 1]] <- token
        }
        nodes
    }
    tree()
}
stringify <- function(v) {
    switch(v$kind,
        absent = "", string = v$data, integer = sprintf("%.0f", v$data),
        boolean = if (v$data) "true" else "false",
        list = paste(vapply(v$data, stringify, character(1)), collapse = ", "),
        map = fail("cannot render map"))
}
truthy <- function(v) {
    switch(v$kind, absent = FALSE, boolean = v$data, integer = v$data != 0, string = v$data != "", list = length(v$data) > 0, map = length(v$data) > 0)
}
number <- function(v, filter) {
    if (v$kind == "absent") return(0)
    if (v$kind == "integer") return(v$data)
    if (v$kind == "string" && grepl("^-?[0-9]{1,9}$", v$data)) return(as.numeric(v$data))
    fail(paste0("not a number for '", filter, "'"))
}
apply_filter <- function(v, filter, args) {
    argument <- if (length(args)) args[[1]]$data else NULL
    if (filter %in% c("upper", "lower", "title", "trim")) {
        text <- stringify(v)
        text <- switch(filter, upper = toupper(text), lower = tolower(text), trim = strip_spaces(text), title = {
            letters <- chars(tolower(text))
            for (i in seq_along(letters)) if (i == 1 || letters[i - 1] == " ") letters[i] <- toupper(letters[i])
            paste(letters, collapse = "")
        })
        return(value("string", text))
    }
    if (filter == "length") return(value("integer", if (v$kind %in% c("list", "map")) length(v$data) else nchar(stringify(v))))
    if (filter %in% c("first", "last")) {
        if (v$kind != "list") return(v)
        if (!length(v$data)) return(absent)
        return(v$data[[if (filter == "first") 1 else length(v$data)]])
    }
    if (filter == "reverse") {
        if (v$kind == "list") return(value("list", rev(v$data)))
        if (v$kind == "string") return(value("string", paste(rev(chars(v$data)), collapse = "")))
        return(v)
    }
    if (filter == "items") {
        if (v$kind != "map") return(v)
        return(value("list", lapply(sort(names(v$data), method = "radix"), function(key) value("map", list(key = value("string", key), value = v$data[[key]])))))
    }
    if (filter == "comma") {
        n <- number(v, filter)
        digits <- chars(sprintf("%.0f", abs(n)))
        groups <- split(digits, ceiling(seq_along(digits) / 3 + ((3 - length(digits) %% 3) %% 3) / 3))
        return(value("string", paste0(if (n < 0) "-" else "", paste(vapply(groups, paste, character(1), collapse = ""), collapse = ","))))
    }
    if (filter %in% c("sum", "min", "max")) {
        if (v$kind != "list") return(value("integer", number(v, filter)))
        numbers <- vapply(v$data, function(item) number(item, filter), numeric(1))
        if (!length(numbers) && filter != "sum") return(absent)
        return(value("integer", switch(filter, sum = sum(numbers), min = min(numbers), max = max(numbers))))
    }
    if (filter == "default") return(if (truthy(v)) v else args[[1]])
    if (filter == "eq") return(value("boolean", stringify(v) == stringify(args[[1]])))
    if (filter %in% c("pad", "lpad", "truncate", "replace", "join")) {
        if (filter == "join" && v$kind == "list") return(value("string", paste(vapply(v$data, stringify, character(1)), collapse = argument)))
        text <- stringify(v)
        if (filter %in% c("pad", "lpad")) {
            padding <- strrep(if (length(args) == 2) args[[2]]$data else " ", max(0, argument - nchar(text)))
            text <- if (filter == "pad") paste0(text, padding) else paste0(padding, text)
        } else if (filter == "truncate" && nchar(text) > argument) {
            text <- paste0(text_slice(text, 1, argument), "...")
        } else if (filter == "replace") {
            pieces <- character()
            position <- 1
            repeat {
                at <- find_from(text, argument, position)
                if (at < 0) break
                pieces <- c(pieces, text_slice(text, position, at - 1), args[[2]]$data)
                position <- at + nchar(argument)
            }
            text <- paste0(c(pieces, text_slice(text, position)), collapse = "")
        }
        return(value("string", text))
    }
    if (filter %in% c("sort", "pluck")) {
        if (v$kind != "list") return(v)
        keys <- lapply(v$data, function(item) {
            if (filter == "sort" && !length(args)) item else if (item$kind == "map" && argument %in% names(item$data)) item$data[[argument]] else absent
        })
        if (filter == "pluck") return(value("list", keys))
        ranks <- vapply(keys, function(k) switch(k$kind, absent = 0, integer = 1, string = 2, boolean = 3, 4), numeric(1))
        numeric_keys <- vapply(keys, function(k) if (k$kind %in% c("integer", "boolean")) as.numeric(k$data) else 0, numeric(1))
        string_keys <- vapply(keys, function(k) if (k$kind == "string") k$data else "", character(1))
        return(value("list", v$data[order(ranks, numeric_keys, string_keys, seq_along(keys), method = "radix")]))
    }
    n <- number(v, filter)
    result <- switch(filter, add = n + argument, sub = n - argument, mul = n * argument,
                     div = floor(n / argument), mod = n - argument * floor(n / argument), gt = n > argument, lt = n < argument)
    value(if (filter %in% c("gt", "lt")) "boolean" else "integer", result)
}
resolve <- function(name, contexts, loops) {
    if (name == ".") return(list(found = TRUE, value = contexts[[length(contexts)]]))
    if (startsWith(name, "@")) {
        if (!length(loops)) return(list(found = FALSE, value = absent))
        loop <- loops[[length(loops)]]
        output <- switch(name, "@index" = value("integer", loop$i), "@number" = value("integer", loop$i + 1), "@first" = value("boolean", loop$i == 0), "@last" = value("boolean", loop$i == loop$n - 1))
        return(list(found = TRUE, value = output))
    }
    parts <- lapply(strsplit(name, ".", fixed = TRUE)[[1]], function(part) if (grepl("^[0-9]+$", part)) as.numeric(part) else part)
    found <- FALSE
    for (context in rev(contexts)) {
        if (has_part(context, parts[[1]])) {
            found <- TRUE
            break
        }
    }
    if (!found) return(list(found = FALSE, value = absent))
    for (part in parts) {
        if (!has_part(context, part)) return(list(found = FALSE, value = absent))
        context <- get_part(context, part)
    }
    list(found = TRUE, value = context)
}
evaluate <- function(token, contexts, loops) {
    expression <- token$expression
    resolved <- resolve(expression$name, contexts, loops)
    if (strict && token$kind %in% c("variable", "raw") && !resolved$found) fail(paste0("missing '", expression$name, "'"))
    output <- resolved$value
    for (filter in expression$filters) output <- apply_filter(output, filter$name, filter$args)
    output
}
escape_html <- function(text) {
    replacements <- c("&" = "&amp;", "<" = "&lt;", ">" = "&gt;", '"' = "&quot;", "'" = "&#39;")
    paste(vapply(chars(text), function(char) if (char %in% names(replacements)) replacements[[char]] else char, character(1)), collapse = "")
}
render <- function(nodes, contexts, loops, depth) {
    output <- character()
    for (token in nodes) {
        text <- tryCatch({
            if (token$kind == "text") {
                token$text
            } else if (token$kind %in% c("variable", "raw")) {
                result <- stringify(evaluate(token, contexts, loops))
                if (token$kind == "variable") escape_html(result) else result
            } else if (token$kind == "section") {
                v <- evaluate(token, contexts, loops)
                pieces <- character()
                if (v$kind == "list") {
                    for (i in seq_along(v$data)) pieces <- c(pieces, render(token$children, c(contexts, list(v$data[[i]])), c(loops, list(list(i = i - 1, n = length(v$data)))), depth))
                } else if (truthy(v)) {
                    pieces <- render(token$children, c(contexts, list(v)), loops, depth)
                }
                paste(pieces, collapse = "")
            } else if (token$kind == "inverted") {
                if (!truthy(evaluate(token, contexts, loops))) render(token$children, contexts, loops, depth) else ""
            } else if (token$kind == "partial") {
                name <- token$text
                if (!(name %in% names(partials))) fail(paste0("unknown partial '", name, "'"))
                if (depth == 8) fail(paste0("partial depth exceeded at '", name, "'"))
                body <- lapply(partials[[name]], function(entry) {
                    if (entry$text != "") entry$text <- paste0(token$indent, entry$text)
                    entry
                })
                render(analyze(body), contexts, loops, depth + 1)
            } else ""
        }, template_error = function(e) {
            if (is.null(e$line)) e$line <- token$line
            stop(e)
        })
        output <- c(output, text)
    }
    paste(output, collapse = "")
}
render_template <- function(name, line) {
    if (!(name %in% names(templates))) {
        cat(sprintf("TEMPLATE %s ERROR line %d: unknown template '%s'\n", name, line, name))
        return(invisible(NULL))
    }
    tryCatch({
        result <- render(analyze(templates[[name]]), list(root), list(), 0)
        count <- if (result == "") 0 else sum(chars(result) == "\n") + if (endsWith(result, "\n")) 0 else 1
        cat(sprintf("TEMPLATE %s OK lines=%d chars=%d\n", name, count, nchar(result)))
        cat(result)
        if (result != "" && !endsWith(result, "\n")) cat("\n")
    }, template_error = function(e) cat(sprintf("TEMPLATE %s ERROR line %d: %s\n", name, e$line, e$message)))
}
dump_leaves <- function(v, path = "") {
    output <- character()
    if (v$kind == "map" && length(v$data)) {
        for (key in sort(names(v$data), method = "radix")) output <- c(output, dump_leaves(v$data[[key]], if (path == "") key else paste0(path, ".", key)))
    } else if (v$kind == "list" && length(v$data)) {
        for (i in seq_along(v$data)) output <- c(output, dump_leaves(v$data[[i]], paste0(path, "[", i - 1, "]")))
    } else if (path != "") {
        notation <- if (v$kind == "string") {
            escaped <- vapply(chars(v$data), function(char) switch(char, "\\" = "\\\\", '"' = '\\"', "\n" = "\\n", char), character(1))
            paste0('"', paste(escaped, collapse = ""), '"')
        } else if (v$kind == "map") "{}" else if (v$kind == "list") "[]" else stringify(v)
        output <- paste0(path, " = ", notation)
    }
    output
}
input <- readLines(file("stdin"), warn = FALSE)
position <- 1
while (position <= length(input)) {
    command <- input[position]
    line <- position
    position <- position + 1
    if (command == "END") break
    at <- regexpr(" ", command, fixed = TRUE)[1]
    kind <- if (at < 0) command else substr(command, 1, at - 1)
    name <- if (at < 0) "" else substring(command, at + 1)
    if (kind %in% c("DATA", "PARTIAL", "TEMPLATE")) {
        ending <- switch(kind, DATA = "ENDDATA", PARTIAL = "ENDPARTIAL", TEMPLATE = "ENDTEMPLATE")
        body <- list()
        while (input[position] != ending) {
            body[[length(body) + 1]] <- list(text = input[position], line = position)
            position <- position + 1
        }
        position <- position + 1
        if (kind == "DATA") {
            data_block(body)
        } else if (kind == "PARTIAL") {
            tryCatch({
                analyze(body)
                action <- if (name %in% names(partials)) "REPLACED" else "DEFINED"
                partials[name] <- list(body)
                cat(sprintf("PARTIAL %s %s lines=%d\n", name, action, length(body)))
            }, template_error = function(e) cat(sprintf("PARTIAL %s ERROR line %d: %s\n", name, e$line, e$message)))
        } else {
            templates[name] <- list(body)
            render_template(name, line)
        }
    } else if (kind == "RENDER") {
        render_template(name, line)
    } else if (kind == "DUMP") {
        leaves <- dump_leaves(root)
        cat(sprintf("DUMP leaves=%d\n", length(leaves)))
        if (length(leaves)) cat(paste0(leaves, "\n"), sep = "")
    } else if (kind == "STRICT") {
        strict <- name == "ON"
        cat(command, "\n", sep = "")
    } else if (kind == "RESET") {
        root <- value("map", list())
        partials <- list()
        templates <- list()
        cat("RESET\n")
    }
}
