valid_name <- function(name) {
    characters <- strsplit(name, "", fixed = TRUE)[[1L]]
    length(characters) > 0L && (letter(characters[1L]) || characters[1L] == "_") && all(vapply(characters, name_character, logical(1L)))
}
valid_filename <- function(name) {
    characters <- strsplit(name, "", fixed = TRUE)[[1L]]
    length(characters) > 0L && characters[1L] != "." && all(vapply(characters, function(character) {
        letter(character) || digit(character) || character %in% c(".", "_", "-")
    }, logical(1L)))
}
parse_arguments <- function(lines) {
    options <- operands <- list()
    for (line in lines) {
        if (startsWith(line, "-F ")) {
            options[[length(options) + 1L]] <- list(name = "FS", value = substring(line, 4L))
        } else if (startsWith(line, "-v ")) {
            assignment <- substring(line, 4L)
            equals <- literal_index(assignment, "=")
            options[[length(options) + 1L]] <- list(name = substr(assignment, 1L, equals - 1L), value = substring(assignment, equals + 1L))
        } else {
            equals <- literal_index(line, "=")
            name <- if (equals > 0L) substr(line, 1L, equals - 1L) else ""
            operand <- if (equals > 0L && valid_name(name)) {
                record(kind = "assignment", name = name, value = substring(line, equals + 1L), records = 0L)
            } else record(kind = "file", name = line, value = "", records = 0L)
            operands[[length(operands) + 1L]] <- operand
        }
    }
    list(options = options, operands = operands)
}
read_records <- function(name) readLines(file.path("input", name), warn = FALSE)
new_output <- function() record(head = NULL, tail = NULL, opened = FALSE, writes = 0L, bytes = 0L, chunks = 0L)
append_output <- function(output, text) {
    force(text)
    chunk <- record(text = text, next_chunk = NULL)
    if (is.null(output$head)) output$head <- chunk else output$tail$next_chunk <- chunk
    output$tail <- chunk
    output$writes <- output$writes + 1L
    output$bytes <- output$bytes + nchar(text)
    output$chunks <- output$chunks + 1L
}
content <- function(output) {
    parts <- character(output$chunks)
    chunk <- output$head
    index <- 1L
    while (!is.null(chunk)) {
        parts[index] <- chunk$text
        chunk <- chunk$next_chunk
        index <- index + 1L
    }
    paste0(parts, collapse = "")
}
new_streams <- function() record(stdout = new_output(), outputs = new_map(), output_order = character(), inputs = new_map(), input_order = character())
write_output <- function(streams, text, name = NULL, mode = NULL, position = NULL) {
    force(text)
    if (is.null(name)) {
        append_output(streams$stdout, text)
        return(invisible(NULL))
    }
    if (!valid_filename(name) || name %in% c("stdout.txt", "stats.txt")) runtime_issue(position, "invalid output file name")
    if (!map_has(streams$outputs, name)) {
        map_set(streams$outputs, name, new_output())
        streams$output_order <- c(streams$output_order, name)
    }
    output <- map_get(streams$outputs, name)
    if (!output$opened) {
        output$opened <- TRUE
        if (mode == ">") {
            output$head <- output$tail <- NULL
            output$bytes <- output$chunks <- 0L
        }
    }
    append_output(output, text)
}
getline_input <- function(streams, name) {
    if (!map_has(streams$inputs, name)) {
        map_set(streams$inputs, name, record(opened = FALSE, ever_opened = FALSE, lines = character(), position = 1L, reads = 0L))
        streams$input_order <- c(streams$input_order, name)
    }
    source <- map_get(streams$inputs, name)
    if (!source$opened) {
        path <- file.path("input", name)
        if (!valid_filename(name) || !file.exists(path) || dir.exists(path)) return(list(status = -1L, line = NULL))
        source$lines <- read_records(name)
        source$position <- 1L
        source$opened <- source$ever_opened <- TRUE
    }
    if (source$position > length(source$lines)) return(list(status = 0L, line = NULL))
    line <- source$lines[source$position]
    source$position <- source$position + 1L
    source$reads <- source$reads + 1L
    list(status = 1L, line = line)
}
close_streams <- function(streams, name) {
    closed <- FALSE
    for (table in list(streams$outputs, streams$inputs)) {
        if (map_has(table, name)) {
            stream <- map_get(table, name)
            if (stream$opened) {
                stream$opened <- FALSE
                closed <- TRUE
            }
        }
    }
    if (closed) 0L else -1L
}
save_streams <- function(streams) {
    writeChar(content(streams$stdout), "output/stdout.txt", eos = NULL, useBytes = TRUE)
    for (name in streams$output_order) writeChar(content(map_get(streams$outputs, name)), file.path("output", name), eos = NULL, useBytes = TRUE)
}
