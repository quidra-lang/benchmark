new_record <- function(...) list2env(list(...), parent = emptyenv())
pp_token <- function(kind, spelling, line, space, hide = character()) list(kind = kind, spelling = spelling, line = line, space = space, hide = hide)
token_with <- function(token, kind = token$kind, spelling = token$spelling, line = token$line, space = token$space, hide = token$hide) pp_token(kind, spelling, line, space, hide)
PUNCTUATORS <- strsplit("... <<= >>= -> ++ -- << >> <= >= == != && || *= /= %= += -= &= ^= |= ## [ ] ( ) { } . & * + - ~ ! / % < > ^ | ? : ; = , #", " ")[[1L]]
identifier_start <- function(character) grepl("^[A-Za-z_]$", character)
digit <- function(character) grepl("^[0-9]$", character)
character_at <- function(text, index) if (index < 1L || index > nchar(text)) "" else substr(text, index, index)
read_token <- function(text, position = 1L, header = FALSE) {
  character <- character_at(text, position)
  if (header && character == "<") {
    suffix <- substr(text, position + 1L, nchar(text))
    closing <- regexpr(">", suffix, fixed = TRUE)[[1L]]
    newline <- regexpr("\n", suffix, fixed = TRUE)[[1L]]
    if (closing > 0L && (newline < 0L || closing < newline)) return(list(kind = "header", spelling = substr(text, position, position + closing), end = position + closing + 1L))
  }
  if (identifier_start(character)) {
    ending <- position + 1L
    while (identifier_start(character_at(text, ending)) || digit(character_at(text, ending))) ending <- ending + 1L
    return(list(kind = "identifier", spelling = substr(text, position, ending - 1L), end = ending))
  }
  if (digit(character) || (character == "." && digit(character_at(text, position + 1L)))) {
    ending <- position + 1L
    while (ending <= nchar(text)) {
      current <- character_at(text, ending)
      if (current %in% c("e", "E", "p", "P") && character_at(text, ending + 1L) %in% c("+", "-")) {
        ending <- ending + 2L
      } else if (identifier_start(current) || digit(current) || current == ".") {
        ending <- ending + 1L
      } else {
        break
      }
    }
    return(list(kind = "number", spelling = substr(text, position, ending - 1L), end = ending))
  }
  if (character %in% c('"', "'")) {
    ending <- position + 1L
    while (ending <= nchar(text) && character_at(text, ending) != "\n") {
      if (character_at(text, ending) == character) return(list(kind = if (character == '"') "string" else "character", spelling = substr(text, position, ending), end = ending + 1L))
      ending <- ending + if (character_at(text, ending) == "\\" && ending < nchar(text) && character_at(text, ending + 1L) != "\n") 2L else 1L
    }
  }
  for (punctuator in PUNCTUATORS) if (startsWith(substring(text, position), punctuator)) return(list(kind = "punctuator", spelling = punctuator, end = position + nchar(punctuator)))
  list(kind = "other", spelling = character, end = position + 1L)
}
splice_lines <- function(text) {
  input <- strsplit(text, "", fixed = TRUE)[[1L]]
  characters <- character(length(input))
  positions <- integer(length(input))
  index <- line <- 1L
  used <- 0L
  while (index <= length(input)) {
    if (input[[index]] == "\\" && index < length(input) && input[[index + 1L]] == "\n") {
      index <- index + 2L
      line <- line + 1L
      next
    }
    used <- used + 1L
    characters[[used]] <- input[[index]]
    positions[[used]] <- line
    if (input[[index]] == "\n") line <- line + 1L
    index <- index + 1L
  }
  list(text = paste(characters[seq_len(used)], collapse = ""), positions = positions[seq_len(used)])
}

scan_tokens <- function(text, positions, start = 1L) {
  lines <- tokens <- list()
  index <- 1L
  spaced <- TRUE
  while (index <= nchar(text)) {
    pair <- substr(text, index, index + 1L)
    if (character_at(text, index) == " ") {
      spaced <- TRUE
      index <- index + 1L
    } else if (character_at(text, index) == "\n") {
      ending <- positions[[index]]
      lines[[length(lines) + 1L]] <- list(tokens = tokens, start = start, end = ending)
      tokens <- list()
      start <- ending + 1L
      spaced <- TRUE
      index <- index + 1L
    } else if (pair == "/*") {
      closing <- regexpr("*/", substring(text, index + 2L), fixed = TRUE)[[1L]]
      index <- if (closing < 0L) nchar(text) + 1L else index + closing + 3L
      spaced <- TRUE
    } else if (pair == "//") {
      closing <- regexpr("\n", substring(text, index + 2L), fixed = TRUE)[[1L]]
      index <- if (closing < 0L) nchar(text) + 1L else index + closing + 1L
      spaced <- TRUE
    } else {
      header <- length(tokens) == 2L && tokens[[1L]]$spelling == "#" && tokens[[2L]]$spelling == "include"
      read <- read_token(text, index, header)
      tokens[[length(tokens) + 1L]] <- pp_token(read$kind, read$spelling, positions[[index]], spaced)
      index <- read$end
      spaced <- FALSE
    }
  }
  if (length(tokens)) lines[[length(lines) + 1L]] <- list(tokens = tokens, start = start, end = tail(positions, 1L))
  lines
}
lex_source <- function(text) {
  spliced <- splice_lines(text)
  scan_tokens(spliced$text, spliced$positions)
}
lex_definition <- function(text, line) {
  text <- paste0(text, "\n")
  lines <- scan_tokens(text, rep(line, nchar(text)), line)
  do.call(c, lapply(lines, function(logical) logical$tokens))
}
render <- function(tokens) {
  pieces <- character()
  for (index in seq_along(tokens)) pieces <- c(pieces, paste0(if (index > 1L && tokens[[index]]$space) " " else "", tokens[[index]]$spelling))
  paste(pieces, collapse = "")
}
single_token <- function(text) {
  if (!nzchar(text) || startsWith(text, "//") || startsWith(text, "/*")) return(NULL)
  read <- read_token(text)
  if (read$end == nchar(text) + 1L) read$kind else NULL
}
integer_text <- function(value) if (value == 0) "0" else sprintf("%.0f", value)
