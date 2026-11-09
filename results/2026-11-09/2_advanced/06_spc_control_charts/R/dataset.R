CONTROL_CONSTANTS <- rbind(
  c(1.880, 2.659, 0, 3.267, 0, 3.267, 1.128, 0.7979),
  c(1.023, 1.954, 0, 2.568, 0, 2.574, 1.693, 0.8862),
  c(0.729, 1.628, 0, 2.266, 0, 2.282, 2.059, 0.9213),
  c(0.577, 1.427, 0, 2.089, 0, 2.114, 2.326, 0.9400),
  c(0.483, 1.287, 0.030, 1.970, 0, 2.004, 2.534, 0.9515),
  c(0.419, 1.182, 0.118, 1.882, 0.076, 1.924, 2.704, 0.9594),
  c(0.373, 1.099, 0.185, 1.815, 0.136, 1.864, 2.847, 0.9650),
  c(0.337, 1.032, 0.239, 1.761, 0.184, 1.816, 2.970, 0.9693),
  c(0.308, 0.975, 0.284, 1.716, 0.223, 1.777, 3.078, 0.9727)
)
colnames(CONTROL_CONSTANTS) <- c("a2", "a3", "b3", "b4", "d3", "d4", "d2", "c4")

control_constants <- function(size) as.list(CONTROL_CONSTANTS[size - 1L, ])

read_numeric_rows <- function(path) {
  lines <- readLines(path, warn = FALSE)[-1L]
  lapply(lines, function(line) as.numeric(strsplit(line, ",", fixed = TRUE)[[1L]]))
}

read_measurements <- function(path) vapply(read_numeric_rows(path), function(row) row[3L], numeric(1L))

read_attributes <- function(path) {
  lapply(read_numeric_rows(path), function(row) list(number = as.integer(row[1L]), inspected = row[2L], defectives = row[3L], defects = row[4L]))
}

read_settings <- function(path) {
  settings <- list(rules = list())
  integer_fields <- c("lsl", "usl", "target", "subgroup_size", "phase1_subgroups", "max_passes", "ma_span", "event_gap", "histogram_bin", "rolling_window", "rolling_step")
  for (line in readLines(path, warn = FALSE)) {
    words <- strsplit(line, " ", fixed = TRUE)[[1L]]
    name <- words[1L]
    if (name == "rules") settings$rules[[words[2L]]] <- as.integer(words[-c(1L, 2L)])
    else if (name == "characteristic") settings[[name]] <- words[2L]
    else settings[[name]] <- if (name %in% integer_fields) as.integer(words[2L]) else as.numeric(words[2L])
  }
  settings
}
