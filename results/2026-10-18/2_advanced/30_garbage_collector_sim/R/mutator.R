COMMAND_NAMES <- c("ALLOC", "PUSH", "LOAD", "POP", "SET", "OVERWRITE", "CHECKPOINT")
COMMAND_FORMS <- list(
    ALLOC = c("number", "number"),
    PUSH = "source",
    LOAD = c("number", "number"),
    POP = "number",
    SET = c("number", "number", "source"),
    OVERWRITE = c("number", "source"),
    CHECKPOINT = "label"
)
read_config <- function(path) {
    config <- list(heap_size = 0L, width = 0L, collectors = list(), maps = character(), windows = integer())
    for (tokens in strsplit(readLines(path), " ", fixed = TRUE)) {
        keyword <- tokens[1L]
        if (keyword == "HEAP") config$heap_size <- as.integer(tokens[2L]) else if (keyword == "COLLECTOR") {
            entry <- list(
                name = tokens[2L],
                kind = tokens[3L],
                young = if (length(tokens) > 3L) as.integer(tokens[4L]) else 0L,
                age = if (length(tokens) > 4L) as.integer(tokens[5L]) else 0L
            )
            config$collectors <- c(config$collectors, list(entry))
        } else if (keyword == "MAPS") config$maps <- tokens[-1L] else if (keyword == "MMU") config$windows <- as.integer(tokens[-1L]) else config$width <- as.integer(tokens[2L])
    }
    config
}
is_number <- function(token) grepl("^(0|[1-9][0-9]{0,3})$", token)
is_label <- function(token) grepl("^[a-z0-9_]{1,16}$", token)
parse_command <- function(line, text) {
    tokens <- strsplit(paste0(text, "~"), " ", fixed = TRUE)[[1L]]
    last <- length(tokens)
    tokens[last] <- substr(tokens[last], 1L, nchar(tokens[last]) - 1L)
    failure <- function(reason) list(command = NULL, reason = reason)
    form <- COMMAND_FORMS[[tokens[1L]]]
    if (is.null(form) || length(tokens) != length(form) + 1L) return(failure("syntax"))
    for (i in seq_along(form)) {
        token <- tokens[i + 1L]
        valid <- if (form[i] == "number") is_number(token) else if (form[i] == "source") token == "-" || is_number(token) else is_label(token)
        if (!valid) return(failure("syntax"))
    }
    name <- tokens[1L]
    command <- list(
        line = line,
        name = name,
        pointers = 0L,
        data = 0L,
        slot = 0L,
        field = 0L,
        source = -1L,
        count = 0L,
        label = ""
    )
    source_value <- function(token) if (token == "-") -1L else as.integer(token)
    if (name == "ALLOC") {
        command$pointers <- as.integer(tokens[2L])
        command$data <- as.integer(tokens[3L])
    } else if (name == "PUSH") command$source <- source_value(tokens[2L]) else if (name == "LOAD") {
        command$slot <- as.integer(tokens[2L])
        command$field <- as.integer(tokens[3L])
    } else if (name == "POP") command$count <- as.integer(tokens[2L]) else if (name == "SET") {
        command$slot <- as.integer(tokens[2L])
        command$field <- as.integer(tokens[3L])
        command$source <- source_value(tokens[4L])
    } else if (name == "OVERWRITE") {
        command$slot <- as.integer(tokens[2L])
        command$source <- source_value(tokens[3L])
    } else command$label <- tokens[2L]
    if ((name == "ALLOC" && (command$pointers > 6L || command$data > 24L)) || (name == "POP" && command$count == 0L)) return(failure("range"))
    list(command = command, reason = NULL)
}
read_script <- function(path) {
    lines <- readLines(path)
    lapply(seq_along(lines), function(i) parse_command(i, lines[i]))
}
