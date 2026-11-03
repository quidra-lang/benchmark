lp_name <- function(word) grepl("^[a-z][a-z0-9_]*$", word) && !word %in% c("bounds", "integer", "binary", "free", "inf")
parse_expression <- function(words) {
  terms <- list()
  index <- 1L
  sign <- 1L
  if (length(words) && words[[1L]] == "-") {
    index <- 2L
    sign <- -1L
  }
  while (index <= length(words)) {
    coefficient <- read_number(words[[index]])
    if (!is.null(coefficient)) {
      if (index == length(words) || !lp_name(words[[index + 1L]])) return(NULL)
      name <- words[[index + 1L]]
      index <- index + 2L
    } else if (lp_name(words[[index]])) {
      coefficient <- fraction(1)
      name <- words[[index]]
      index <- index + 1L
    } else {
      return(NULL)
    }
    terms[[length(terms) + 1L]] <- list(name = name, coefficient = sign * coefficient)
    if (index > length(words)) return(terms)
    if (!words[[index]] %in% c("+", "-")) return(NULL)
    sign <- if (words[[index]] == "+") 1L else -1L
    index <- index + 1L
  }
  NULL
}
named_expression <- function(words) {
  if (length(words) < 2L || !endsWith(words[[1L]], ":")) return(NULL)
  name <- substr(words[[1L]], 1L, nchar(words[[1L]]) - 1L)
  terms <- parse_expression(words[-1L])
  if (lp_name(name) && !is.null(terms)) list(name = name, terms = terms) else NULL
}
parse_constraint <- function(words, line) {
  size <- length(words)
  if (size < 4L || !words[[size - 1L]] %in% c("<=", ">=", "=")) return(NULL)
  rhs <- read_number(words[[size]], TRUE)
  named <- named_expression(head(words, -2L))
  if (is.null(rhs) || is.null(named)) return(NULL)
  list(line = line, name = named$name, terms = named$terms, comparison = words[[size - 1L]], rhs = rhs)
}
parse_bound <- function(words, line) {
  if (length(words) == 2L && lp_name(words[[1L]]) && words[[2L]] == "free") {
    return(list(line = line, name = words[[1L]], kind = "both", lower = NULL, upper = NULL))
  }
  if (length(words) == 3L && lp_name(words[[1L]])) {
    name <- words[[1L]]
    operator <- words[[2L]]
    word <- words[[3L]]
    value <- read_number(word, TRUE)
    if (operator == ">=" && (!is.null(value) || word == "-inf")) return(list(line = line, name = name, kind = "lower", lower = value, upper = NULL))
    if (operator == "<=" && (!is.null(value) || word == "inf")) return(list(line = line, name = name, kind = "upper", lower = NULL, upper = value))
    if (operator == "=" && !is.null(value)) return(list(line = line, name = name, kind = "both", lower = value, upper = value))
  }
  if (length(words) == 5L && words[[2L]] == "<=" && words[[4L]] == "<=" && lp_name(words[[3L]])) {
    lower <- read_number(words[[1L]], TRUE)
    upper <- read_number(words[[5L]], TRUE)
    if ((!is.null(lower) || words[[1L]] == "-inf") && (!is.null(upper) || words[[5L]] == "inf")) return(list(line = line, name = words[[3L]], kind = "both", lower = lower, upper = upper))
  }
  NULL
}
parse_block <- function(name, body, end_line) {
  parsed <- list(name = name, error = NULL, direction = NULL, objective = NULL,
                 constraints = list(), bounds = list(), integers = list(), binaries = list())
  state <- "A"
  for (record in body) {
    line <- record$line
    text <- record$text
    words <- strsplit(text, " ", fixed = TRUE)[[1L]]
    accepted <- FALSE
    if (state == "A" && text %in% c("maximize", "minimize")) {
      parsed$direction <- text
      state <- "B"
      accepted <- TRUE
    } else if (state == "B") {
      named <- named_expression(words)
      if (!is.null(named)) {
        parsed$objective <- named$terms
        state <- "C"
        accepted <- TRUE
      }
    } else if (state == "C" && text == "subject to") {
      state <- "D"
      accepted <- TRUE
    } else if (state %in% c("D", "E")) {
      if (state == "E" && text %in% c("bounds", "integer", "binary")) {
        state <- switch(text, bounds = "F", integer = "G", binary = "H")
        accepted <- TRUE
      } else {
        item <- parse_constraint(words, line)
        if (!is.null(item)) {
          parsed$constraints[[length(parsed$constraints) + 1L]] <- item
          state <- "E"
          accepted <- TRUE
        }
      }
    } else if (state == "F") {
      if (text %in% c("integer", "binary")) {
        state <- if (text == "integer") "G" else "H"
        accepted <- TRUE
      } else {
        item <- parse_bound(words, line)
        if (!is.null(item)) {
          parsed$bounds[[length(parsed$bounds) + 1L]] <- item
          accepted <- TRUE
        }
      }
    } else if (state %in% c("G", "H")) {
      if (state == "G" && text == "binary") {
        state <- "H"
        accepted <- TRUE
      } else if (all(vapply(words, lp_name, logical(1L)))) {
        key <- if (state == "G") "integers" else "binaries"
        parsed[[key]][[length(parsed[[key]]) + 1L]] <- list(line = line, names = words)
        accepted <- TRUE
      }
    }
    if (!accepted) {
      parsed$error <- list(line = line, message = "syntax error")
      return(parsed)
    }
  }
  if (state %in% c("A", "B", "C", "D")) parsed$error <- list(line = end_line, message = "syntax error")
  parsed
}
read_models <- function() {
  records <- readLines("input/models.lp", warn = FALSE)
  models <- body <- list()
  name <- NULL
  for (line in seq_along(records)) {
    text <- records[[line]]
    if (!nzchar(text) || startsWith(text, "#")) next
    if (is.null(name)) {
      name <- strsplit(text, " ", fixed = TRUE)[[1L]][[2L]]
      body <- list()
    } else if (text == "end") {
      models[[length(models) + 1L]] <- parse_block(name, body, line)
      name <- NULL
    } else {
      body[[length(body) + 1L]] <- list(line = line, text = text)
    }
  }
  models
}
read_settings <- function() {
  lines <- readLines("input/params.txt", warn = FALSE)
  level <- as.integer(strsplit(lines[[1L]], " ", fixed = TRUE)[[1L]][[2L]])
  limit <- as.integer(strsplit(lines[[2L]], " ", fixed = TRUE)[[1L]][[2L]])
  logs <- limits <- list()
  for (text in tail(lines, -2L)) {
    if (!nzchar(text)) next
    words <- strsplit(text, " ", fixed = TRUE)[[1L]]
    if (words[[1L]] == "log") logs[[words[[2L]]]] <- as.integer(words[[3L]]) else limits[[words[[2L]]]] <- as.integer(words[[3L]])
  }
  list(level = level, limit = limit, logs = logs, limits = limits)
}
