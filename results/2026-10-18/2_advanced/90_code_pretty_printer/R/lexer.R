KEYWORDS <- strsplit("int float bool string void if else while for return break continue true false switch case default", " ")[[1L]]
TYPE_NAMES <- c("int", "float", "bool", "string", "void")
DOUBLE_SYMBOLS <- c("<=", ">=", "==", "!=", "&&", "||", "+=", "-=", "*=", "/=", "%=")
SINGLE_SYMBOLS <- strsplit("+-*/%<>=!()[]{},;.?:", "", fixed = TRUE)[[1L]]
ASSIGNMENTS <- c("=", "+=", "-=", "*=", "/=", "%=")
source_error <- function(line, column, message) {
  stop(structure(list(message = message, line = line, column = column),
                 class = c("source_error", "error", "condition")))
}
new_record <- function(...) list2env(list(...), parent = emptyenv())
new_token <- function(kind, text, line, column, blank, index) {
  new_record(kind = kind, text = text, line = line, column = column,
             blank = blank, index = index, leading = list(), trailing = list(),
             allowed = FALSE, trailing_comma = FALSE, original_trailing = FALSE)
}
character_at <- function(text, index) {
  if (index < 1L || index > nchar(text)) "" else substr(text, index, index)
}
code_letter <- function(character) grepl("^[A-Za-z]$", character)
code_digit <- function(character) grepl("^[0-9]$", character)
trim_spaces <- function(text) sub(" +$", "", text)
lexical_analysis <- function(lines) {
  tokens <- comments <- items <- list()
  previous_line <- 0L
  for (line_number in seq_along(lines)) {
    text <- lines[[line_number]]
    column <- 1L
    while (column <= nchar(text)) {
      character <- character_at(text, column)
      if (character == " ") {
        column <- column + 1L
        next
      }
      first <- column
      pair <- substr(text, column, column + 1L)
      if (pair == "//") {
        kind <- "line_comment"
        value <- trim_spaces(substr(text, column, nchar(text)))
        column <- nchar(text) + 1L
      } else if (pair == "/*") {
        ending <- regexpr("*/", substr(text, column + 2L, nchar(text)), fixed = TRUE)[[1L]]
        if (ending < 0L) source_error(line_number, first, "unterminated comment")
        column <- column + ending + 3L
        kind <- "block_comment"
        value <- substr(text, first, column - 1L)
      } else if (code_letter(character) || character == "_") {
        column <- column + 1L
        while (code_letter(character_at(text, column)) || code_digit(character_at(text, column)) || character_at(text, column) == "_") column <- column + 1L
        value <- substr(text, first, column - 1L)
        kind <- if (value %in% KEYWORDS) "keyword" else "identifier"
      } else if (code_digit(character)) {
        column <- column + 1L
        while (code_digit(character_at(text, column))) column <- column + 1L
        if (character_at(text, column) == "." && code_digit(character_at(text, column + 1L))) {
          column <- column + 2L
          while (code_digit(character_at(text, column))) column <- column + 1L
        }
        kind <- "number"
        value <- substr(text, first, column - 1L)
      } else if (character == '"') {
        column <- column + 1L
        closed <- FALSE
        while (column <= nchar(text)) {
          next_character <- character_at(text, column)
          if (next_character == "\\") {
            column <- column + 2L
          } else if (next_character == '"') {
            column <- column + 1L
            closed <- TRUE
            break
          } else {
            column <- column + 1L
          }
        }
        if (!closed) source_error(line_number, first, "unterminated string")
        kind <- "string"
        value <- substr(text, first, column - 1L)
      } else if (pair %in% DOUBLE_SYMBOLS) {
        column <- column + 2L
        kind <- "symbol"
        value <- pair
      } else if (character %in% SINGLE_SYMBOLS) {
        column <- column + 1L
        kind <- "symbol"
        value <- character
      } else {
        source_error(line_number, first, paste0("unexpected character '", character, "'"))
      }
      blank <- max(0L, line_number - previous_line - 1L)
      previous_line <- line_number
      if (endsWith(kind, "_comment")) {
        entry <- new_record(kind = kind, text = value, line = line_number,
                            column = first, blank = blank, own_line = FALSE)
        comments[[length(comments) + 1L]] <- entry
      } else {
        entry <- new_token(kind, value, line_number, first, blank, length(tokens) + 1L)
        tokens[[length(tokens) + 1L]] <- entry
      }
      items[[length(items) + 1L]] <- entry
    }
  }
  ending <- new_token("end", "", length(lines) + 1L, 1L, 0L, length(tokens) + 1L)
  ending$allowed <- TRUE
  tokens[[length(tokens) + 1L]] <- ending
  list(tokens = tokens, comments = comments, items = items)
}
