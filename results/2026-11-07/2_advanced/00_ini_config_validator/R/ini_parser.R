is_name <- function(text) grepl("\\A[a-z][a-z0-9_]*\\z", text, perl = TRUE)
is_section_name <- function(text) grepl("\\A[a-z][a-z0-9_]*(?:\\.[a-z][a-z0-9_]*)*\\z", text, perl = TRUE)

trim_segments <- function(segments) {
    segments[1L] <- sub("^ +", "", segments[1L])
    segments[length(segments)] <- sub(" +$", "", segments[length(segments)])
    segments
}

parse_document <- function(name, physical) {
    document <- list(statements = list(), diagnostics = list())
    section <- NULL; base <- NULL; assigned <- list()
    report <- function(number, code, message) {
        document$diagnostics[[length(document$diagnostics) + 1L]] <<- list(document = name, line = number, code = code, message = message)
    }
    add <- function(kind, number, target, value = "") {
        document$statements[[length(document$statements) + 1L]] <<- list(kind = kind, line = number, target = target, value = value)
    }
    for (line in logical_lines(physical)) {
        number <- line$number
        if (!is.null(line$error)) {
            report(number, line$error$code, line$error$message)
            next
        }
        segments <- trim_segments(line$segments); first <- segments[1L]
        if (length(segments) == 1L && first == "") next
        if (startsWith(first, "[")) {
            inside <- substr(first, 2L, nchar(first) - 1L)
            parts <- cut_first(inside, ":")
            header <- trim_spaces(parts$before); parent <- trim_spaces(parts$after)
            relative <- startsWith(header, ".") && is_section_name(substring(header, 2L))
            valid <- length(segments) == 1L && endsWith(first, "]") && (!parts$found || is_section_name(parent)) && (relative || is_section_name(header))
            if (!valid || (relative && is.null(base))) {
                report(number, "E_SECTION", if (valid) "relative section without base" else "invalid section header")
                section <- NULL
            } else {
                if (relative) section <- paste0(base, header) else { section <- header; base <- header }
                if (parts$found) add("inherit", number, section, parent)
            }
        } else if (startsWith(first, "@")) {
            words <- strsplit(first, " +", perl = TRUE)[[1L]]
            if (length(segments) != 1L || length(words) != 2L || !(words[1L] %in% c("@include", "@unset")) || !is_name(words[2L])) {
                report(number, "E_SYNTAX", "invalid directive")
            } else if (words[1L] == "@include") {
                add("include", number, words[2L])
            } else if (is.null(section)) {
                report(number, "E_NO_SECTION", "no current section")
            } else {
                add("unset", number, paste0(section, ".", words[2L]))
            }
        } else {
            outside <- segments[seq.int(1L, length(segments), by = 2L)]
            if (!any(grepl("=", outside, fixed = TRUE))) {
                report(number, "E_SYNTAX", "invalid line"); next
            }
            pair <- cut_first(first, "=")
            if (!pair$found) { report(number, "E_SYNTAX", "invalid key"); next }
            key <- trim_spaces(pair$before); append <- endsWith(key, "+")
            if (append) key <- sub(" +$", "", substr(key, 1L, nchar(key) - 1L))
            if (!is_name(key)) { report(number, "E_SYNTAX", "invalid key"); next }
            value_segments <- trim_segments(c(pair$after, segments[-1L]))
            if (length(value_segments) == 1L) {
                value <- value_segments[1L]
            } else if (length(value_segments) == 3L && value_segments[1L] == "" && value_segments[3L] == "") {
                value <- value_segments[2L]
            } else {
                report(number, "E_SYNTAX", "invalid value"); next
            }
            if (is.null(section)) { report(number, "E_NO_SECTION", "no current section"); next }
            full <- paste0(section, ".", key)
            if (!append) {
                if (!is.null(assigned[[full]])) report(number, "W_DUPLICATE", paste0(full, " already set at line ", assigned[[full]]))
                assigned[[full]] <- number
            }
            add(if (append) "append" else "assign", number, full, value)
        }
    }
    document
}
