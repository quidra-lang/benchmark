csv_rows <- function(name) strsplit(readLines(file.path("input", name))[-1L], ",", fixed = TRUE)
read_inputs <- function() {
    series <- list()
    for (row in csv_rows("series.csv")) {
        name <- row[1L]
        if (is.null(series[[name]])) series[[name]] <- list(
            name = name,
            periods = character(),
            raw = integer(),
            events = list(),
            policy = NULL
        )
        series[[name]]$periods <- c(series[[name]]$periods, row[2L])
        series[[name]]$raw <- c(series[[name]]$raw, if (row[3L] == "NA") NA_integer_ else as.integer(row[3L]))
    }
    for (row in csv_rows("events.csv")) series[[row[1L]]]$events[[row[2L]]] <- row[3L]
    for (row in csv_rows("inventory.csv")) series[[row[1L]]]$policy <- list(
        on_hand = as.integer(row[2L]),
        lead_time = as.integer(row[3L]),
        review = as.integer(row[4L]),
        service = as.numeric(row[5L])
    )
    settings <- list()
    for (fields in strsplit(readLines("input/params.txt"), " ", fixed = TRUE)) {
        key <- fields[1L]
        values <- fields[-1L]
        settings[[key]] <- if (key %in% c(
            "alpha",
            "beta",
            "gamma",
            "phi",
            "interval"
        )) as.numeric(values) else if (key == "ljung_box") as.integer(values) else if (key == "outlier") as.numeric(values[1L]) else as.integer(values[1L])
    }
    list(records = unname(series), settings = settings)
}
next_month <- function(period) {
    parts <- as.integer(strsplit(period, "-", fixed = TRUE)[[1L]])
    year <- parts[1L] + parts[2L] %/% 12L
    month <- parts[2L] %% 12L + 1L
    sprintf("%04d-%02d", year, month)
}
real_format <- function(value) {
    if (is.na(value)) return("NA")
    text <- sprintf("%.4f", value)
    if (text == "-0.0000") "0.0000" else text
}
write_lines <- function(name, lines) {
    dir.create("output", showWarnings = FALSE)
    writeLines(lines, file.path("output", name), useBytes = TRUE)
}
