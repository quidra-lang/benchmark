KEYWORDS <- strsplit("let rec and in fun if then else match with true false mod val", " ")[[1L]]
SYMBOLS <- strsplit(";; -> :: : || && <= >= <> ; = < > + - * / ^ ( ) [ ] , |", " ")[[1L]]
ESCAPES <- setNames(c("\n", "\t", "\\", '"'), c("n", "t", "\\", '"'))
new_record <- function(...) list2env(list(...), parent = emptyenv())
new_position <- function(filename, line, column) list(filename = filename, line = line, column = column)
new_token <- function(kind, spelling, value, position) list(kind = kind, spelling = spelling, value = value, position = position)
is_name <- function(token) token$kind == "identifier" && token$spelling != "_"
letter <- function(character) grepl("^[A-Za-z]$", character)
word_character <- function(character) grepl("^[A-Za-z0-9_]$", character)
ml_character <- function(source, index) if (index < 1L || index > nchar(source)) "" else substr(source, index, index)
tokenize <- function(source, filename) {
  tokens <- list()
  index <- line <- column <- 1L
  while (index <= nchar(source)) {
    start <- index
    position <- new_position(filename, line, column)
    character <- ml_character(source, index)
    kind <- value <- NULL
    pair <- substr(source, index, index + 1L)
    if (character %in% c(" ", "\n")) {
      index <- index + 1L
    } else if (pair == "(*") {
      closing <- regexpr("*)", substr(source, index + 2L, nchar(source)), fixed = TRUE)[[1L]]
      if (closing < 0L) {
        kind <- "invalid"
        value <- "unterminated comment"
        index <- nchar(source) + 1L
      } else {
        index <- index + closing + 3L
      }
    } else if (grepl("^[0-9]$", character)) {
      index <- index + 1L
      while (grepl("^[0-9]$", ml_character(source, index))) index <- index + 1L
      digits <- sub("^0+", "", substr(source, start, index - 1L))
      if (!nzchar(digits)) digits <- "0"
      if (nchar(digits) > 10L || (nchar(digits) == 10L && as.numeric(digits) > 2147483647)) {
        kind <- "invalid"
        value <- "integer literal too large"
      } else {
        kind <- "integer"
        value <- as.numeric(digits)
      }
    } else if (letter(character) || character == "_") {
      index <- index + 1L
      while (word_character(ml_character(source, index)) || ml_character(source, index) == "'") index <- index + 1L
      value <- substr(source, start, index - 1L)
      kind <- if (value %in% KEYWORDS) value else "identifier"
    } else if (character == "'" && grepl("^[a-z]$", ml_character(source, index + 1L))) {
      index <- index + 2L
      while (word_character(ml_character(source, index))) index <- index + 1L
      kind <- "type_variable"
      value <- substr(source, start, index - 1L)
    } else if (character == '"') {
      index <- index + 1L
      decoded <- character()
      invalid_escape <- FALSE
      while (index <= nchar(source) && !ml_character(source, index) %in% c('"', "\n")) {
        if (ml_character(source, index) == "\\" && index < nchar(source) && ml_character(source, index + 1L) != "\n") {
          escape <- ml_character(source, index + 1L)
          if (escape %in% names(ESCAPES)) decoded <- c(decoded, ESCAPES[[escape]]) else invalid_escape <- TRUE
          index <- index + 2L
        } else {
          decoded <- c(decoded, ml_character(source, index))
          index <- index + 1L
        }
      }
      if (index > nchar(source) || ml_character(source, index) == "\n") {
        kind <- "invalid"
        value <- "unterminated string"
      } else {
        index <- index + 1L
        kind <- if (invalid_escape) "invalid" else "string"
        value <- if (invalid_escape) "invalid escape sequence" else paste(decoded, collapse = "")
      }
    } else if (pair %in% SYMBOLS) {
      index <- index + 2L
      kind <- value <- pair
    } else if (character %in% SYMBOLS) {
      index <- index + 1L
      kind <- value <- character
    } else {
      index <- index + 1L
      kind <- "invalid"
      value <- paste0("illegal character '", character, "'")
    }
    consumed <- substr(source, start, index - 1L)
    if (!is.null(kind)) tokens[[length(tokens) + 1L]] <- new_token(kind, consumed, value, position)
    characters <- strsplit(consumed, "", fixed = TRUE)[[1L]]
    newlines <- which(characters == "\n")
    if (length(newlines)) {
      line <- line + length(newlines)
      column <- length(characters) - tail(newlines, 1L) + 1L
    } else {
      column <- column + nchar(consumed)
    }
  }
  eof_line <- sum(strsplit(source, "", fixed = TRUE)[[1L]] == "\n") + 1L
  tokens[[length(tokens) + 1L]] <- new_token("EOF", "", NULL, new_position(filename, eof_line, 1L))
  tokens
}
