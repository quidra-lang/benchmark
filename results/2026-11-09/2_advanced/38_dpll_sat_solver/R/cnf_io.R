valid_number <- function(token) nchar(token) <= 6L && grepl("^(0|[1-9][0-9]*)$", token)
valid_literal <- function(token) nchar(sub("^-", "", token)) <= 6L && grepl("^(0|-?[1-9][0-9]*)$", token)
input_error <- function(reason) stop(structure(
    list(message = reason, call = NULL),
    class = c("input_error", "error", "condition")
))
read_dimacs <- function(filename) {
  header <- NULL
  clauses <- list()
  partial <- integer()
  lines <- readLines(file.path("input", filename), warn = FALSE)
  for (number in seq_along(lines)) {
    line <- lines[[number]]
    tokens <- strsplit(trimws(line), " +")[[1L]]
    if (startsWith(line, "c") || !length(tokens) || identical(tokens, "")) next
    if (tokens[[1L]] == "p") {
      if (!is.null(header)) input_error(paste("duplicate header at line", number))
      if (length(tokens) != 4L || tokens[[2L]] != "cnf" || !valid_number(tokens[[3L]]) || !valid_number(tokens[[4L]])) input_error(paste(
          "bad header at line",
          number
      ))
      header <- as.integer(tokens[3L:4L])
      next
    }
    if (is.null(header)) input_error("missing header")
    for (token in tokens) {
      if (!valid_literal(token)) input_error(paste("bad token", token, "at line", number))
      literal <- as.integer(token)
      if (abs(literal) > header[[1L]]) input_error(paste("literal out of range", token, "at line", number))
      if (literal == 0L) {
        clauses[[length(clauses) + 1L]] <- partial
        partial <- integer()
      } else partial <- c(partial, literal)
    }
  }
  if (is.null(header)) input_error("missing header")
  if (length(partial)) input_error("unterminated clause")
  if (length(clauses) != header[[2L]]) input_error(paste0(
      "clause count mismatch header=",
      header[[2L]],
      " found=",
      length(clauses)
  ))
  list(variables = header[[1L]], clauses = clauses)
}
model_lines <- function(assignment) {
  variables <- seq_along(assignment)
  tokens <- c(as.character(ifelse(assignment, variables, -variables)), "0")
  vapply(
      seq.int(1L, length(tokens), by = 10L),
      function(start) paste(
          "v",
          paste(tokens[seq.int(start, min(start + 9L, length(tokens)))], collapse = " ")
      ),
      ""
  )
}
