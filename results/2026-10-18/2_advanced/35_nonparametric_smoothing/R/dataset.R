hundredths <- function(text) as.integer(gsub(".", "", text, fixed = TRUE))
read_dataset <- function() {
  series <- list()
  for (line in readLines(file.path("input", "series.csv"), warn = FALSE)[-1L]) {
    parts <- strsplit(line, ",", fixed = TRUE)[[1L]]
    name <- parts[[1L]]
    point <- c(hundredths(parts[[2L]]), hundredths(parts[[3L]]))
    if (is.null(series[[name]])) series[[name]] <- matrix(integer(), 0L, 2L)
    series[[name]] <- rbind(series[[name]], point)
  }
  series <- lapply(series, function(points) points[order(points[, 1L]), , drop = FALSE])
  tests <- lapply(readLines(file.path("input", "test_points.csv"), warn = FALSE)[-1L], function(line) {
    parts <- strsplit(line, ",", fixed = TRUE)[[1L]]
    list(name = parts[[1L]], position = hundredths(parts[[2L]]))
  })
  settings <- list()
  for (line in readLines(file.path("input", "params.txt"), warn = FALSE)) {
    parts <- strsplit(line, " ", fixed = TRUE)[[1L]]
    settings[[parts[[1L]]]] <- parts[-1L]
  }
  for (key in c(
      "ROBUST_ITERATIONS",
      "CV_FOLDS",
      "GRID_POINTS",
      "BOOTSTRAP",
      "PLOT_SIZE"
  )) settings[[key]] <- as.integer(settings[[key]])
  for (key in c("BAND_Z", "OUTLIER_THRESHOLD")) settings[[key]] <- as.numeric(settings[[key]])
  list(series = series, tests = tests, settings = settings)
}
