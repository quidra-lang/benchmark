UNINITIALIZED <- list(kind = "uninitialized", text = "", numeric = 0L)
WHITESPACE <- c(" ", "\t", "\n")
number <- function(value) list(kind = "number", text = "", numeric = as.integer(value))
string_value <- function(text) list(kind = "string", text = text, numeric = 0L)
numeric_prefix <- function(text) {
    characters <- strsplit(text, "", fixed = TRUE)[[1L]]
    index <- 1L
    sign <- 1L
    value <- 0L
    while (index <= length(characters) && characters[index] %in% WHITESPACE) index <- index + 1L
    if (index <= length(characters) && characters[index] %in% c("+", "-")) {
        sign <- if (characters[index] == "-") -1L else 1L
        index <- index + 1L
    }
    while (index <= length(characters) && digit(characters[index])) {
        value <- value * 10L + utf8ToInt(characters[index]) - 48L
        index <- index + 1L
    }
    sign * value
}
input_value <- function(text) {
    characters <- strsplit(text, "", fixed = TRUE)[[1L]]
    beginning <- 1L
    finish <- length(characters)
    while (beginning <= finish && characters[beginning] %in% WHITESPACE) beginning <- beginning + 1L
    while (beginning <= finish && characters[finish] %in% WHITESPACE) finish <- finish - 1L
    if (beginning <= finish && characters[beginning] %in% c("+", "-")) beginning <- beginning + 1L
    numeric <- beginning <= finish && all(vapply(characters[seq.int(beginning, finish)], digit, logical(1L)))
    if (numeric) list(kind = "strnum", text = text, numeric = numeric_prefix(text)) else string_value(text)
}
to_number <- function(value) if (value$kind == "string") numeric_prefix(value$text) else value$numeric
to_string <- function(value) if (value$kind == "number") as.character(value$numeric) else if (value$kind == "uninitialized") "" else value$text
truth <- function(value) if (value$kind == "string") value$text != "" else value$numeric != 0L
ascii_compare <- function(a, b) {
    first <- utf8ToInt(a)
    second <- utf8ToInt(b)
    for (index in seq_len(min(length(first), length(second)))) {
        if (first[index] != second[index]) return(if (first[index] < second[index]) -1L else 1L)
    }
    as.integer(length(first) > length(second)) - as.integer(length(first) < length(second))
}
compare_values <- function(first, second) {
    if (first$kind != "string" && second$kind != "string") {
        a <- to_number(first)
        b <- to_number(second)
        return(as.integer(a > b) - as.integer(a < b))
    }
    ascii_compare(to_string(first), to_string(second))
}
new_map <- function() record(buckets = new.env(hash = TRUE, parent = emptyenv()), size = 0L)
new_array <- function() {
    array <- new_map()
    class(array) <- c("awk_array", "environment")
    array
}
map_hash <- function(key) {
    hash <- 0L
    for (code in utf8ToInt(key)) hash <- (hash * 31L + code) %% 1000003L
    paste0("k", hash)
}
map_entry <- function(map, key) {
    bucket <- map$buckets[[map_hash(key)]]
    for (entry in bucket) if (identical(entry$key, key)) return(entry)
    NULL
}
map_has <- function(map, key) !is.null(map_entry(map, key))
map_get <- function(map, key, default = UNINITIALIZED, create = FALSE) {
    entry <- map_entry(map, key)
    if (!is.null(entry)) return(entry$value)
    if (create) map_set(map, key, default)
    default
}
map_set <- function(map, key, value) {
    force(value)
    entry <- map_entry(map, key)
    if (is.null(entry)) {
        hash <- map_hash(key)
        bucket <- map$buckets[[hash]]
        bucket[[length(bucket) + 1L]] <- record(key = key, value = value)
        map$buckets[[hash]] <- bucket
        map$size <- map$size + 1L
    } else entry$value <- value
    invisible(value)
}
map_remove <- function(map, key) {
    hash <- map_hash(key)
    bucket <- map$buckets[[hash]]
    for (index in seq_along(bucket)) {
        if (identical(bucket[[index]]$key, key)) {
            bucket[[index]] <- NULL
            if (length(bucket)) map$buckets[[hash]] <- bucket else rm(list = hash, envir = map$buckets)
            map$size <- map$size - 1L
            return(invisible(NULL))
        }
    }
}
map_clear <- function(map) {
    map$buckets <- new.env(hash = TRUE, parent = emptyenv())
    map$size <- 0L
}
map_keys <- function(map) {
    result <- character(map$size)
    index <- 1L
    for (hash in ls(map$buckets, all.names = TRUE)) {
        for (entry in map$buckets[[hash]]) {
            result[index] <- entry$key
            index <- index + 1L
        }
    }
    result
}
ordered_subscripts <- function(keys) {
    integer_form <- vapply(keys, function(key) {
        if (key == "0") return(TRUE)
        digits <- if (startsWith(key, "-")) substring(key, 2L) else key
        characters <- strsplit(digits, "", fixed = TRUE)[[1L]]
        length(characters) > 0L && characters[1L] %in% as.character(1L:9L) && all(vapply(characters, digit, logical(1L)))
    }, logical(1L))
    integers <- keys[integer_form]
    c(integers[order(as.integer(integers))], sort(keys[!integer_form], method = "radix"))
}
literal_index <- function(text, sought, start = 1L) {
    if (sought == "" || nchar(sought) > nchar(text) - start + 1L) return(0L)
    for (index in seq.int(start, nchar(text) - nchar(sought) + 1L)) {
        if (substr(text, index, index + nchar(sought) - 1L) == sought) return(index)
    }
    0L
}
split_pieces <- function(text, separator) {
    if (text == "") return(character())
    if (separator == "") return(strsplit(text, "", fixed = TRUE)[[1L]])
    pieces <- character()
    if (separator != " ") {
        beginning <- 1L
        repeat {
            found <- literal_index(text, separator, beginning)
            if (found == 0L) break
            pieces <- c(pieces, if (found == beginning) "" else substr(text, beginning, found - 1L))
            beginning <- found + nchar(separator)
        }
        return(c(pieces, if (beginning > nchar(text)) "" else substring(text, beginning)))
    }
    characters <- strsplit(text, "", fixed = TRUE)[[1L]]
    beginning <- 0L
    for (index in seq_along(characters)) {
        if (characters[index] %in% WHITESPACE) {
            if (beginning != 0L) {
                pieces <- c(pieces, substr(text, beginning, index - 1L))
                beginning <- 0L
            }
        } else if (beginning == 0L) beginning <- index
    }
    if (beginning != 0L) pieces <- c(pieces, substring(text, beginning))
    pieces
}
new_record <- function(special) record(special = special, zero = string_value(""), fields = list())
set_record <- function(record, text) {
    force(text)
    record$zero <- input_value(text)
    record$fields <- lapply(split_pieces(text, to_string(record$special("FS"))), input_value)
}
read_field <- function(record, index) {
    if (index == 0L) record$zero else if (index <= length(record$fields)) record$fields[[index]] else UNINITIALIZED
}
rebuild_record <- function(record) {
    fields <- vapply(record$fields, to_string, character(1L))
    record$zero <- input_value(paste0(fields, collapse = to_string(record$special("OFS"))))
}
write_field <- function(record, index, value) {
    force(value)
    if (index == 0L) {
        set_record(record, to_string(value))
        return(invisible(NULL))
    }
    while (length(record$fields) < index) record$fields[[length(record$fields) + 1L]] <- string_value("")
    record$fields[[index]] <- value
    rebuild_record(record)
}
resize_fields <- function(record, size) {
    if (size < length(record$fields)) record$fields <- head(record$fields, size)
    while (length(record$fields) < size) record$fields[[length(record$fields) + 1L]] <- string_value("")
    rebuild_record(record)
}
quoted_value <- function(text) {
    pieces <- vapply(strsplit(text, "", fixed = TRUE)[[1L]], function(character) {
        if (character == "\"") "\\\"" else if (character == "\\") "\\\\" else if (character == "\n") "\\n" else if (character == "\t") "\\t" else {
            code <- utf8ToInt(character)
            if (code >= 32L && code <= 126L) character else paste0("\\", sprintf("%03o", code))
        }
    }, character(1L))
    paste0("\"", paste0(pieces, collapse = ""), "\"")
}
describe_value <- function(value) {
    if (value$kind == "number") return(as.character(value$numeric))
    if (value$kind == "uninitialized") return("(uninitialized)")
    paste0(quoted_value(value$text), if (value$kind == "strnum") " (strnum)" else "")
}
