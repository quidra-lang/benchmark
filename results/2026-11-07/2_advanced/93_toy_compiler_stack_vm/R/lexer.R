KEYWORDS <- strsplit("int bool void true false if else while for break continue return print read", " ")[[1L]]
PAIRS <- c("<=", ">=", "==", "!=", "&&", "||")
SYMBOLS <- strsplit("+-*/%<>=!(){}[],;", "", fixed = TRUE)[[1L]]
new_record <- function(...) list2env(list(...), parent = emptyenv())
compile_error <- function(kind, position, message) stop(structure(list(kind = kind, position = position, message = message), class = c("compile_error", "error", "condition")))
letter <- function(character) grepl("^[A-Za-z]$", character)
digit <- function(character) grepl("^[0-9]$", character)
character_at <- function(source, index) if (index < 1L || index > nchar(source)) "" else substr(source, index, index)
tokenize <- function(lines) {
  source <- paste0(paste(vapply(lines, function(line) line$text, character(1L)), collapse = "\n"), "\n")
  line <- lines[[1L]]$number
  column <- index <- 1L
  tokens <- list()
  while (index <= nchar(source)) {
    character <- character_at(source, index)
    start <- c(line, column)
    if (character == " ") {
      index <- index + 1L
      column <- column + 1L
      next
    }
    if (character == "\n") {
      index <- index + 1L
      line <- line + 1L
      column <- 1L
      next
    }
    pair <- substr(source, index, index + 1L)
    if (pair == "//") {
      ending <- regexpr("\n", substr(source, index, nchar(source)), fixed = TRUE)[[1L]]
      column <- column + ending - 1L
      index <- index + ending - 1L
      next
    }
    if (pair == "/*") {
      ending <- regexpr("*/", substr(source, index + 2L, nchar(source)), fixed = TRUE)[[1L]]
      if (ending < 0L) compile_error("lexical", start, "unterminated comment")
      stop <- index + ending + 3L
      comment <- substr(source, index, stop - 1L)
      characters <- strsplit(comment, "", fixed = TRUE)[[1L]]
      newlines <- which(characters == "\n")
      if (length(newlines)) {
        line <- line + length(newlines)
        column <- length(characters) - tail(newlines, 1L) + 1L
      } else {
        column <- column + nchar(comment)
      }
      index <- stop
      next
    }
    stop <- index + 1L
    if (letter(character) || character == "_") {
      while (letter(character_at(source, stop)) || digit(character_at(source, stop)) || character_at(source, stop) == "_") stop <- stop + 1L
      spelling <- substr(source, index, stop - 1L)
      kind <- if (spelling %in% KEYWORDS) "keyword" else "identifier"
    } else if (digit(character)) {
      while (digit(character_at(source, stop))) stop <- stop + 1L
      spelling <- substr(source, index, stop - 1L)
      if (as.numeric(spelling) > 2147483647) compile_error("lexical", start, "integer literal too large")
      kind <- "integer"
    } else if (pair %in% PAIRS) {
      stop <- stop + 1L
      spelling <- pair
      kind <- "symbol"
    } else if (character %in% SYMBOLS) {
      spelling <- character
      kind <- "symbol"
    } else {
      compile_error("lexical", start, paste0("unexpected character '", character, "'"))
    }
    tokens[[length(tokens) + 1L]] <- list(kind = kind, spelling = spelling, position = start)
    column <- column + stop - index
    index <- stop
  }
  last <- lines[[length(lines)]]
  tokens[[length(tokens) + 1L]] <- list(kind = "end", spelling = "", position = c(last$number, nchar(last$text) + 1L))
  tokens
}
