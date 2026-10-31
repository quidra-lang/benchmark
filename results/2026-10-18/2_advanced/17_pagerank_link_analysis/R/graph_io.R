read_lines <- function(path) readLines(path, warn = FALSE)
read_input <- function() {
  pages <- lapply(read_lines("input/pages.csv")[-1L], function(line) {
    fields <- strsplit(line, ",", fixed = TRUE)[[1L]]
    list(id = as.integer(fields[1L]), host = fields[2L], title = fields[3L], words = strsplit(fields[3L], " ", fixed = TRUE)[[1L]])
  })
  link_lines <- read_lines("input/links.csv")[-1L]
  records <- lapply(seq_along(link_lines), function(index) {
    fields <- as.integer(strsplit(link_lines[index], ",", fixed = TRUE)[[1L]])
    list(line = index + 1L, source = fields[1L], target = fields[2L])
  })
  query_lines <- read_lines("input/queries.txt")
  queries <- lapply(seq_along(query_lines), function(index) {
    fields <- strsplit(query_lines[index], " | ", fixed = TRUE)[[1L]]
    list(number = index, words = strsplit(fields[1L], " ", fixed = TRUE)[[1L]],
      seeds = as.integer(strsplit(fields[2L], " ", fixed = TRUE)[[1L]]))
  })
  entries <- list()
  for (line in read_lines("input/params.txt")) {
    fields <- strsplit(line, " ", fixed = TRUE)[[1L]]
    entries[[fields[1L]]] <- fields[-1L]
  }
  number <- function(key) as.numeric(entries[[key]][1L])
  settings <- list(damping = number("DAMPING"), iterations = number("PAGERANK_ITERATIONS"),
    tolerance = number("TOLERANCE"), sweep = as.numeric(entries$DAMPING_SWEEP), trusted = as.integer(entries$TRUSTED),
    spam_top = number("SPAM_TOP"), spam_threshold = number("SPAM_THRESHOLD"), hits_iterations = number("HITS_ITERATIONS"),
    top_k = number("TOP_K"), root_limit = number("ROOT_LIMIT"), neighbor_limit = number("NEIGHBOR_LIMIT"))
  list(pages = pages, records = records, queries = queries, settings = settings)
}
