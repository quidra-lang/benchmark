args <- commandArgs(FALSE)
script <- sub("^--file=", "", args[startsWith(args, "--file=")])
source_dir <- if (length(script)) dirname(script[1L]) else "."
for (module in c("lexer", "ini_parser", "interpolate", "schema", "emitter")) {
    source(file.path(source_dir, paste0(module, ".R")))
}

read_lines <- function(path) readLines(path, warn = FALSE)
section_of <- function(key) sub("\\.[^.]+$", "", key)
key_name <- function(key) sub("^.*\\.", "", key)
key_order <- function(keys) keys[order(section_of(keys), key_name(keys), method = "radix")]
matches <- function(pattern, text) grepl(paste0("\\A(?:", pattern, ")\\z"), text, perl = TRUE)
decimal <- function(text) as.numeric(text)
lower_ascii <- function(text) chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", text)

parse_int <- function(text) {
    if (!matches("[+-]?(?:0[xX][0-9a-fA-F]{1,10}|[0-9](?:_?[0-9])*)", text)) return(NULL)
    negative <- startsWith(text, "-")
    digits <- sub("^[+-]", "", text)
    if (startsWith(lower_ascii(digits), "0x")) {
        chars <- strsplit(lower_ascii(substring(digits, 3L)), "", fixed = TRUE)[[1L]]
        value <- 0
        for (char in chars) value <- value * 16 + match(char, c(as.character(0:9), letters[1:6])) - 1
    } else {
        digits <- gsub("_", "", digits, fixed = TRUE)
        if (nchar(digits) > 12L) return(NULL)
        value <- decimal(digits)
    }
    if (negative) -value else value
}

parse_size <- function(text) {
    if (!matches("[0-9]{1,6}(?:\\.[0-9]{1,3})?(?:[bB]|[kKmMgG][bB])?", text)) return(NULL)
    unit <- lower_ascii(sub("^[0-9.]+", "", text))
    factor <- if (unit == "") 1 else unname(c(b = 1, kb = 1024, mb = 1048576, gb = 1073741824)[unit])
    parts <- split_keep(sub("[A-Za-z]+$", "", text), ".")
    value <- decimal(parts[1L]) * unname(factor)
    if (length(parts) == 2L) {
        scaled <- decimal(parts[2L]) * unname(factor)
        divisor <- 10^nchar(parts[2L])
        if (scaled %% divisor != 0) return(NULL)
        value <- value + scaled / divisor
    }
    value
}

parse_duration <- function(text) {
    if (matches("[0-9]{1,6}", text)) return(decimal(text))
    if (!nzchar(text) || !matches("(?:[0-9]{1,6}h)?(?:[0-9]{1,6}m)?(?:[0-9]{1,6}s)?", text)) return(NULL)
    parts <- regmatches(text, gregexpr("[0-9]+[hms]", text, perl = TRUE))[[1L]]
    sum(vapply(parts, function(part) {
        decimal(sub("[hms]$", "", part)) * c(h = 3600, m = 60, s = 1)[substring(part, nchar(part))]
    }, numeric(1L)))
}

parse_host <- function(text) {
    parts <- split_keep(text, ".")
    if (matches("[0-9.]*", text)) {
        valid <- length(parts) == 4L && all(vapply(parts, function(part) {
            matches("(?:0|[1-9][0-9]{0,2})", part) && decimal(part) <= 255
        }, logical(1L)))
        return(if (valid) text else NULL)
    }
    if (nchar(text) > 253L || !all(vapply(parts, function(part) {
        matches("[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?", part)
    }, logical(1L)))) return(NULL)
    lower_ascii(text)
}

parse_path <- function(text) {
    if (!nzchar(text) || grepl("[ \\n\\t]", text, perl = TRUE)) return(NULL)
    absolute <- startsWith(text, "/")
    parts <- character()
    for (part in split_keep(text, "/")) {
        if (part %in% c("", ".")) next
        if (part != "..") {
            parts <- c(parts, part)
        } else if (length(parts) && tail(parts, 1L) != "..") {
            parts <- head(parts, -1L)
        } else if (absolute) {
            return(NULL)
        } else {
            parts <- c(parts, part)
        }
    }
    if (absolute) paste0("/", paste(parts, collapse = "/")) else if (length(parts)) paste(parts, collapse = "/") else "."
}

parse_url <- function(text) {
    halves <- cut_first(text, "://")
    if (!halves$found || !matches("[A-Za-z][A-Za-z0-9+.-]*", halves$before)) return(NULL)
    if (grepl("[?#]", halves$after)) return(NULL)
    rest <- cut_first(halves$after, "/")
    authority <- cut_first(rest$before, ":")
    host <- parse_host(authority$before)
    path <- parse_path(paste0("/", rest$after))
    if (is.null(host) || is.null(path)) return(NULL)
    scheme <- lower_ascii(halves$before)
    port <- ""
    if (authority$found) {
        text_port <- authority$after
        if (!matches("[1-9][0-9]{0,4}", text_port) || decimal(text_port) > 65535) return(NULL)
        default <- switch(scheme, http = 80, https = 443, NA_real_)
        if (is.na(default) || decimal(text_port) != default) port <- paste0(":", text_port)
    }
    paste0(scheme, "://", host, port, path)
}

parse_date <- function(text) {
    if (!matches("[0-9]{4}-[0-9]{2}-[0-9]{2}", text)) return(NULL)
    parts <- as.numeric(split_keep(text, "-"))
    year <- parts[1L]; month <- parts[2L]; day <- parts[3L]
    if (year < 1 || month < 1 || month > 12) return(NULL)
    days <- c(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)[month]
    if (month == 2 && ((year %% 4 == 0 && year %% 100 != 0) || year %% 400 == 0)) days <- 29
    if (day >= 1 && day <= days) text else NULL
}

parse_scalar <- function(kind, text, values = character()) {
    switch(kind,
        string = text,
        int = parse_int(text),
        bool = if (lower_ascii(text) %in% c("true", "yes", "on", "1")) TRUE else if (lower_ascii(text) %in% c("false", "no", "off", "0")) FALSE else NULL,
        enum = { index <- match(lower_ascii(text), lower_ascii(values)); if (is.na(index)) NULL else values[index] },
        size = parse_size(text), duration = parse_duration(text), host = parse_host(text),
        path = parse_path(text), url = parse_url(text), date = parse_date(text)
    )
}

type_error <- function(key, kind, values, display) {
    if (kind == "enum") {
        list(code = "E_ENUM", message = paste0(key, ": ", display, " is not one of ", paste(values, collapse = ",")))
    } else {
        list(code = "E_TYPE", message = paste0(key, ": ", display, " is not a valid ", kind))
    }
}

normalize_value <- function(key, spec, text, report) {
    checked <- function(text) if (spec$secret) MASK else string_notation(text)
    if (spec$kind == "list") {
        items <- if (trim_spaces(text) == "") character() else vapply(split_keep(text, ","), trim_spaces, character(1L))
        if (any(items == "")) {
            report("W_EMPTY_ITEM", paste0(key, ": empty list item ignored"))
            items <- items[items != ""]
        }
        value <- list()
        for (item in items) {
            parsed <- parse_scalar(spec$item, item, spec$values)
            if (is.null(parsed)) return(list(error = type_error(key, spec$item, spec$values, paste0("item ", checked(item)))))
            value[[length(value) + 1L]] <- parsed
        }
        if (spec$unique && length(value)) {
            notation <- vapply(value, function(item) value_notation(spec$item, "", item), character(1L))
            repeated <- duplicated(notation)
            if (any(repeated)) report("W_DUPLICATE_ITEM", paste0(key, ": duplicate items removed"))
            value <- value[!repeated]
        }
    } else {
        value <- parse_scalar(spec$kind, text, spec$values)
        if (is.null(value)) return(list(error = type_error(key, spec$kind, spec$values, checked(text))))
    }
    if (!is.null(spec$range)) {
        bound <- function(text) {
            if (text == "") NULL else if (spec$kind %in% c("string", "list")) decimal(text) else parse_scalar(spec$kind, text)
        }
        lower <- bound(spec$range[1L]); upper <- bound(spec$range[2L])
        measure <- switch(spec$kind, string = nchar(value, type = "bytes"), list = length(value), value)
        if ((!is.null(lower) && measure < lower) || (!is.null(upper) && measure > upper)) {
            display <- if (spec$kind == "string") paste0("length ", measure) else if (spec$kind == "list") paste0("count ", measure) else if (spec$secret) MASK else value_notation(spec$kind, spec$item, value)
            bound_text <- function(value) if (is.null(value)) "" else if (is.numeric(value)) number_text(value) else value
            return(list(error = list(code = "E_RANGE", message = paste0(key, ": ", display, " is out of range ", bound_text(lower), "..", bound_text(upper)))))
        }
    }
    list(value = value)
}

new_library <- function(directory) {
    documents <- new.env(parent = emptyenv())
    function(name) {
        if (!exists(name, documents, inherits = FALSE)) {
            path <- file.path(directory, paste0(name, ".ini"))
            assign(name, if (file.exists(path)) parse_document(name, read_lines(path)) else NULL, documents)
        }
        get(name, documents, inherits = FALSE)
    }
}

process_profile <- function(line, number, schema, library, earlier) {
    words <- split_keep(line, " ")
    profile <- list(name = words[1L], root = words[2L], tree = list(), outputs = list())
    configuration <- list(); parents <- list(); diagnostics <- list(); definition_count <- 0
    report <- function(origin, code, message) {
        diagnostics[[length(diagnostics) + 1L]] <<- list(document = origin$document, line = origin$line, code = code, message = message)
    }
    define <- function(key, value, origin) {
        definition_count <<- definition_count + 1
        history <- configuration[[key]]$history
        if (!length(history) || !identical(tail(history, 1L)[[1L]], origin)) history <- c(history, list(origin))
        configuration[[key]] <<- list(value = value, origin = origin, number = definition_count, history = history)
    }
    tree_line <- function(depth, text) {
        profile$tree[[length(profile$tree) + 1L]] <<- list(depth = depth, text = text)
    }
    apply_document <- function(name, chain) {
        document <- library(name)
        tree_line(length(chain) - 1L, name)
        diagnostics <<- c(diagnostics, document$diagnostics)
        for (statement in document$statements) {
            origin <- list(document = name, line = statement$line)
            key <- statement$target
            if (statement$kind %in% c("assign", "append")) {
                value <- statement$value
                if (statement$kind == "append" && !is.null(configuration[[key]]) && nzchar(configuration[[key]]$value)) value <- paste0(configuration[[key]]$value, ",", value)
                define(key, value, origin)
            } else if (statement$kind == "unset") {
                if (is.null(configuration[[key]])) report(origin, "W_UNSET", paste0(key, " is not set")) else configuration[[key]] <<- NULL
            } else if (statement$kind == "inherit") {
                parents[[key]] <<- list(parent = statement$value, origin = origin)
            } else if (key %in% chain) {
                path <- c(chain[seq.int(match(key, chain), length(chain))], key)
                report(origin, "E_INCLUDE_CYCLE", paste0("include cycle ", paste(path, collapse = " -> ")))
                tree_line(length(chain), paste0(key, " (cycle)"))
            } else if (is.null(library(key))) {
                report(origin, "E_INCLUDE_MISSING", paste0("missing document ", key))
                tree_line(length(chain), paste0(key, " (missing)"))
            } else {
                apply_document(key, c(chain, key))
            }
        }
    }
    apply_document(profile$root, profile$root)
    for (override in words[-c(1L, 2L)]) {
        pair <- cut_first(override, "=")
        define(pair$before, pair$after, list(document = "manifest", line = number))
    }
    own <- configuration
    for (section in names(parents)) {
        declaration <- parents[[section]]
        chain <- section
        repeat {
            last <- tail(chain, 1L)
            if (is.null(parents[[last]]) || parents[[last]]$parent %in% chain) break
            chain <- c(chain, parents[[last]]$parent)
        }
        last <- tail(chain, 1L)
        if (!is.null(parents[[last]])) {
            report(declaration$origin, "E_INHERIT_CYCLE", paste0("inheritance cycle ", paste(c(chain, parents[[last]]$parent), collapse = " -> ")))
            next
        }
        parent <- declaration$parent
        if (is.null(parents[[parent]]) && !any(section_of(names(own)) == parent)) report(declaration$origin, "W_PARENT_EMPTY", paste0("section ", section, " inherits from empty section ", parent))
        for (ancestor in chain[-1L]) {
            for (key in names(own)[section_of(names(own)) == ancestor]) {
                target <- paste0(section, ".", key_name(key))
                if (is.null(configuration[[target]])) configuration[[target]] <- own[[key]]
            }
        }
    }
    for (spec in schema) {
        aliases <- spec$aliases[spec$aliases %in% names(configuration)]
        if (!length(aliases)) next
        candidates <- c(if (spec$pattern %in% names(configuration)) spec$pattern, aliases)
        numbers <- vapply(candidates, function(key) configuration[[key]]$number, numeric(1L))
        winner <- candidates[which.max(numbers)]
        chosen <- configuration[[winner]]
        for (key in candidates) {
            origin <- configuration[[key]]$origin
            if (key != spec$pattern) report(origin, "W_DEPRECATED", paste0(key, " is deprecated, use ", spec$pattern))
            if (key != winner) report(origin, "W_SHADOWED", paste0(key, " is superseded by ", winner, " at ", origin_text(chosen$origin)))
        }
        configuration[[spec$pattern]] <- chosen
        configuration[aliases] <- NULL
    }
    sections <- unique(section_of(names(configuration)))
    for (spec in schema) {
        if (is.null(spec$default)) next
        for (key in target_keys(schema, spec, sections)) {
            if (is.null(configuration[[key]])) define(key, spec$default, list(document = "schema", line = spec$line))
        }
    }
    configured <- names(configuration)
    expanded <- expand_values(configuration, report)
    for (key in key_order(configured)) {
        text <- expanded[[key]]
        if (is.null(text)) next
        definition <- configuration[[key]]
        spec <- spec_for(schema, key)
        if (is.null(spec)) {
            report(definition$origin, "W_UNKNOWN", paste0(key, " is not in the schema"))
            value <- text; notation <- string_notation(text); kind <- "string"; secret <- FALSE
        } else {
            checked <- normalize_value(key, spec, text, function(code, message) report(definition$origin, code, message))
            if (!is.null(checked$error)) {
                report(definition$origin, checked$error$code, checked$error$message)
                next
            }
            value <- checked$value; kind <- spec$kind; secret <- spec$secret
            notation <- value_notation(kind, spec$item, value)
        }
        profile$outputs[[key]] <- list(definition = definition, spec = spec, value = value, notation = notation, kind = kind, secret = secret)
    }
    remove <- character()
    for (key in key_order(names(profile$outputs))) {
        output <- profile$outputs[[key]]
        if (is.null(output$spec$le)) next
        limit_key <- paste0(section_of(key), ".", output$spec$le)
        limit <- profile$outputs[[limit_key]]
        if (!is.null(limit) && limit$kind %in% c("int", "size", "duration") && output$value > limit$value) {
            report(output$definition$origin, "E_ORDER", paste0(key, ": ", shown(output), " is greater than ", limit_key, " (", shown(limit), ")"))
            remove <- c(remove, key)
        }
    }
    profile$outputs[remove] <- NULL
    for (spec in schema) {
        if (!spec$required) next
        for (key in setdiff(target_keys(schema, spec, sections), configured)) {
            message <- NULL
            if (is.null(spec$when)) {
                message <- paste0(key, " is required")
            } else {
                condition_key <- paste0(section_of(key), ".", spec$when)
                condition <- profile$outputs[[condition_key]]
                if (!is.null(condition) && identical(condition$value, TRUE)) message <- paste0(key, " is required when ", condition_key, " is true")
            }
            if (!is.null(message)) report(list(document = profile$root, line = 0), "E_REQUIRED", message)
        }
    }
    for (key in key_order(names(profile$outputs))) {
        output <- profile$outputs[[key]]
        if (is.null(output$spec) || !output$spec$fixed) next
        for (reference in earlier) {
            before <- reference$outputs[[key]]
            if (is.null(before)) next
            if (before$notation != output$notation) {
                report(output$definition$origin, "E_FIXED", paste0(key, ": value differs from profile ", reference$name))
                profile$outputs[[key]] <- NULL
            }
            break
        }
    }
    if (length(diagnostics)) {
        frame <- unique(do.call(rbind, lapply(diagnostics, as.data.frame, stringsAsFactors = FALSE)))
        frame <- frame[order(frame$document, frame$line, frame$code, frame$message, method = "radix"), , drop = FALSE]
        profile$diagnostics <- lapply(seq_len(nrow(frame)), function(i) as.list(frame[i, , drop = FALSE]))
    } else profile$diagnostics <- list()
    profile$errors <- sum(vapply(profile$diagnostics, function(diagnostic) startsWith(diagnostic$code, "E_"), logical(1L)))
    profile$warnings <- length(profile$diagnostics) - profile$errors
    origins <- vapply(profile$outputs, function(output) output$definition$origin$document, character(1L))
    profile$manifest_keys <- sum(origins == "manifest")
    profile$default_keys <- sum(origins == "schema")
    profile$document_keys <- length(origins) - profile$manifest_keys - profile$default_keys
    profile$dropped <- length(configured) - length(profile$outputs)
    profile
}

profile_diff <- function(first, second) {
    diff <- list(first = first$name, second = second$name, added = 0, removed = 0, changed = 0, entries = list())
    for (key in key_order(union(names(first$outputs), names(second$outputs)))) {
        before <- first$outputs[[key]]; after <- second$outputs[[key]]
        if (is.null(before)) {
            sign <- "+"; diff$added <- diff$added + 1L
        } else if (is.null(after)) {
            sign <- "-"; diff$removed <- diff$removed + 1L
        } else if (before$notation != after$notation) {
            sign <- "~"; diff$changed <- diff$changed + 1L
        } else next
        diff$entries[[length(diff$entries) + 1L]] <- list(sign = sign, key = key, before = before, after = after)
    }
    diff
}

main <- function() {
    schema <- load_schema("input/schema.txt")
    library <- new_library("input/conf")
    profiles <- list()
    manifest <- read_lines("input/manifest.txt")
    for (number in seq_along(manifest)) profiles[[number]] <- process_profile(manifest[number], number, schema, library, profiles)
    diffs <- lapply(seq_len(length(profiles) - 1L), function(i) profile_diff(profiles[[i]], profiles[[i + 1L]]))
    write_outputs("output", profiles, diffs)
}

main()
