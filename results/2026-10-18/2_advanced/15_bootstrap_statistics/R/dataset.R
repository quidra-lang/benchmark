hundredths <- function(text) {
  parts <- strsplit(text, ".", fixed = TRUE)[[1L]]
  fraction <- if (length(parts) == 1L) "00" else paste0(parts[2L], strrep("0", 2L - nchar(parts[2L])))
  as.numeric(parts[1L]) * 100 + as.numeric(fraction)
}

load_dataset <- function() {
  groups <- list()
  group_names <- character()
  for (line in readLines("input/samples.csv", warn = FALSE)[-1L]) {
    fields <- strsplit(line, ",", fixed = TRUE)[[1L]]
    index <- match(fields[1L], group_names)
    if (is.na(index)) {
      index <- length(groups) + 1L
      group_names <- c(group_names, fields[1L])
      groups[[index]] <- list(number = index, name = fields[1L], values = numeric())
    }
    groups[[index]]$values <- c(groups[[index]]$values, hundredths(fields[2L]))
  }
  before <- after <- numeric()
  for (line in readLines("input/paired.csv", warn = FALSE)[-1L]) {
    fields <- strsplit(line, ",", fixed = TRUE)[[1L]]
    before <- c(before, hundredths(fields[2L]))
    after <- c(after, hundredths(fields[3L]))
  }
  settings <- list()
  pairs <- list()
  for (line in readLines("input/params.txt", warn = FALSE)) {
    fields <- strsplit(line, " ", fixed = TRUE)[[1L]]
    if (fields[1L] == "compare") pairs[[length(pairs) + 1L]] <- match(fields[2:3], group_names)
    else settings[[fields[1L]]] <- as.numeric(fields[-1L])
  }
  settings$power_sims <- settings$power[1L]
  settings$power_perms <- settings$power[2L]
  list(groups = groups, paired = list(before = before, after = after, differences = after - before),
       pairs = pairs, settings = settings)
}
