decimal_integer <- function(
    text,
    maximum = .Machine$integer.max
) nchar(text) <= maximum && grepl("^(0|[1-9][0-9]*)$", text)
valid_hex_address <- function(text) grepl("^[0-9a-f]{8}$", text)
hex_address <- function(value) sprintf("%08x", as.integer(value))
read_trace <- function() readLines("input/trace.txt", warn = FALSE)

read_config <- function() {
    config <- list(scenarios = list(), regions = list(), watch = integer())
    for (line in readLines("input/config.txt", warn = FALSE)) {
        fields <- strsplit(line, " ", fixed = TRUE)[[1L]]
        kind <- fields[1L]
        if (kind %in% c("CORES", "LINE", "INTERVAL", "TOP")) {
            key <- c(CORES = "cores", LINE = "line_size", INTERVAL = "interval", TOP = "top")[[kind]]
            config[[key]] <- as.integer(fields[2L])
        } else if (kind %in% c("L1", "L2")) {
            prefix <- tolower(kind)
            config[[paste0(prefix, "_size")]] <- as.integer(fields[2L])
            config[[paste0(prefix, "_ways")]] <- as.integer(fields[3L])
        } else if (kind == "LATENCY") {
            for (index in 1:4) config[[c("t1", "t2", "tm", "tb")[index]]] <- as.integer(fields[index + 1L])
        } else if (kind == "SCENARIO") {
            config$scenarios[[length(config$scenarios) + 1L]] <- list(
                name = fields[2L],
                protocol = fields[3L],
                l1 = fields[4L],
                l2 = fields[5L],
                order = length(config$scenarios)
            )
        } else if (kind == "PRIMARY") {
            config$primary <- fields[2L]
        } else if (kind == "REGION") {
            config$regions[[length(config$regions) + 1L]] <- list(
                name = fields[2L],
                low = strtoi(fields[3L], 16L),
                high = strtoi(fields[4L], 16L)
            )
        } else if (kind == "WATCH") {
            config$watch <- c(config$watch, strtoi(fields[2L], 16L) %/% config$line_size)
        }
    }
    config$l1_sets <- config$l1_size %/% (config$line_size * config$l1_ways)
    config$l2_sets <- config$l2_size %/% (config$line_size * config$l2_ways)
    config$cap <- config$l1_sets * config$l1_ways
    config
}

write_lines <- function(filename, lines) {
    dir.create("output", showWarnings = FALSE)
    writeLines(lines, file.path("output", filename), useBytes = TRUE)
}
