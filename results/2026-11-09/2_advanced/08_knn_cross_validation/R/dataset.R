csv_fields <- function(line) strsplit(paste0(line, ","), ",", fixed = TRUE)[[1L]]

read_rows <- function(name) {
  lines <- readLines(file.path("input", name), warn = FALSE)
  header <- csv_fields(lines[1L])
  count <- length(header) - 3L
  rows <- lapply(lines[-1L], function(line) {
    fields <- csv_fields(line)
    list(id = fields[1L], values = as.numeric(fields[seq.int(2L, count + 1L)]), label = fields[count + 2L],
         target = if (nzchar(fields[count + 3L])) as.numeric(fields[count + 3L]) else NA_real_)
  })
  list(features = header[seq.int(2L, count + 1L)], rows = rows)
}

read_dataset <- function() {
  train <- read_rows("train.csv")
  test <- read_rows("test.csv")
  params <- list()
  for (line in readLines("input/params.txt", warn = FALSE)) {
    fields <- strsplit(line, " ", fixed = TRUE)[[1L]]
    name <- fields[1L]
    value <- fields[-1L]
    params[[name]] <- if (name %in% c("SCALINGS", "METRICS", "WEIGHTINGS")) value else as.numeric(value)
  }
  list(features = train$features, train = train$rows, test = test$rows, settings = params)
}
