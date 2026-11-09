COLUMN_TYPES <- c("INT", "STRING", "BOOL", "DATE")
is_leap_year <- function(year) year %% 4L == 0L && (year %% 100L != 0L || year %% 400L == 0L)
month_lengths <- function(year) c(
    31L,
    if (is_leap_year(year)) 29L else 28L,
    31L,
    30L,
    31L,
    30L,
    31L,
    31L,
    30L,
    31L,
    30L,
    31L
)

day_number <- function(text) {
    fields <- as.integer(strsplit(text, "-", fixed = TRUE)[[1L]])
    year <- fields[1L]
    month <- fields[2L]
    previous <- year - 1L
    365L * previous + previous %/% 4L - previous %/% 100L + previous %/% 400L + sum(month_lengths(year)[seq_len(month - 1L)]) + fields[3L] - 1L - 719162L
}

date_text <- function(number) {
    year <- 1970L
    while (number < 0L) {
        year <- year - 1L
        number <- number + (if (is_leap_year(year)) 366L else 365L)
    }
    year_days <- function(year) if (is_leap_year(year)) 366L else 365L
    while (number >= year_days(year)) {
        number <- number - year_days(year)
        year <- year + 1L
    }
    month <- 1L
    lengths <- month_lengths(year)
    while (number >= lengths[month]) {
        number <- number - lengths[month]
        month <- month + 1L
    }
    sprintf("%04d-%02d-%02d", year, month, number + 1L)
}

parse_value <- function(kind, field) {
    if (!nzchar(field)) return(NULL)
    if (kind == "INT") return(as.numeric(field))
    if (kind == "DATE") return(day_number(field))
    if (kind == "BOOL") return(field == "true")
    field
}

value_text <- function(kind, value, null = "NULL") {
    if (is.null(value)) return(null)
    if (kind == "DATE") return(date_text(value))
    if (kind == "BOOL") return(if (value) "true" else "false")
    if (kind == "INT") return(sprintf("%.0f", value))
    value
}

split_fields <- function(text, separator) {
    fields <- strsplit(paste0(text, separator), separator, fixed = TRUE)[[1L]]
    if (!length(fields)) "" else fields
}

read_inputs <- function() {
    columns <- lapply(readLines("input/schema.txt", warn = FALSE), function(line) {
        fields <- strsplit(line, " ", fixed = TRUE)[[1L]]
        list(name = fields[1L], kind = fields[2L], nullable = fields[3L] == "NULLABLE")
    })
    lines <- readLines("input/table.csv", warn = FALSE)[-1L]
    rows <- lapply(lines, function(line) {
        fields <- split_fields(line, ",")
        lapply(seq_along(columns), function(index) parse_value(columns[[index]]$kind, fields[index]))
    })
    options <- list(encoding = list())
    for (line in readLines("input/options.txt", warn = FALSE)) {
        fields <- strsplit(line, " ", fixed = TRUE)[[1L]]
        if (fields[1L] == "encoding") options$encoding[[fields[2L]]] <- fields[3L] else options[[fields[1L]]] <- as.integer(fields[2L])
    }
    hex <- paste0(readLines("input/damaged.hex", warn = FALSE), collapse = "")
    damaged <- vapply(
        seq.int(1L, nchar(hex), by = 2L),
        function(index) strtoi(substr(hex, index, index + 1L), 16L),
        0L
    )
    list(
        columns = columns,
        rows = rows,
        options = options,
        queries = readLines("input/queries.txt", warn = FALSE),
        damaged = damaged
    )
}

write_outputs <- function(outputs) {
    dir.create("output", showWarnings = FALSE)
    for (name in names(outputs)) writeLines(outputs[[name]], file.path("output", name), useBytes = TRUE)
}
