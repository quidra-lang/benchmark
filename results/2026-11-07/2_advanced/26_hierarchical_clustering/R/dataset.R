read_lines <- function(path) readLines(path, warn = FALSE)
read_observations <- function() {
  lines <- read_lines("input/data.csv")
  feature_names <- strsplit(lines[1], ",", fixed = TRUE)[[1]][-c(1, 2)]
  fields <- strsplit(lines[-1], ",", fixed = TRUE)
  observations <- lapply(fields, function(row) list(ident = row[1], label = row[2], values = as.numeric(row[-c(1, 2)])))
  list(feature_names = feature_names, observations = observations)
}
read_settings <- function() {
  entries <- list()
  for (line in read_lines("input/params.txt")) {
    fields <- strsplit(line, " ", fixed = TRUE)[[1]]
    entries[[fields[1]]] <- fields[-1]
  }
  entries
}
write_lines <- function(name, lines) {
  cat(if (length(lines)) paste0(paste(lines, collapse = "\n"), "\n") else "", file = file.path("output", name))
}
