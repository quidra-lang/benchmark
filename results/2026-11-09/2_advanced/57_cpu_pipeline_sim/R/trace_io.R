parse_hex <- function(text) if (grepl("^[0-9a-f]{8}$",text)) strtoi(text,16L) else NA_integer_
parse_register <- function(text) if (grepl(
    "^r([0-9]|[12][0-9]|3[01])$",
    text
)) as.integer(substring(text,2L)) else -1L
read_inputs <- function() {
  config <- list(predictors=list(),variants=list())
  for (line in readLines(file.path("input","config.txt"))) {
    row <- strsplit(line," ",fixed=TRUE)[[1L]]
    key <- row[1L]
    values <- row[-1L]
    if (key %in% c(
        "BTB",
        "RAS",
        "TOP",
        "INTERVAL"
    )) config[[tolower(key)]] <- as.integer(values[1L]) else if (key == "PREDICTOR")
      config$predictors[[length(config$predictors)+1L]] <- list(
          name=values[1L],
          scheme=values[2L],
          parameters=as.integer(values[-c(1L,2L)])
      ) else if (key == "VARIANT")
      config$variants[[length(config$variants)+1L]] <- list(
          name=values[1L],
          forwarding=values[2L] == "ON",
          stage=values[3L],
          latency=as.integer(values[4L])
      ) else if (key == "PRIMARY")
      config$primary <- values else config$window <- as.integer(values)
  }
  list(trace=readLines(file.path("input","trace.txt")),config=config)
}
