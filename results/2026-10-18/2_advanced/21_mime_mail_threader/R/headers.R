ascii_lower <- function(text) chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", text)
chars <- function(text) strsplit(text, "", fixed = TRUE)[[1L]]
split_lf <- function(text) {
  pieces <- strsplit(paste0(text, "\nX"), "\n", fixed = TRUE)[[1L]]
  pieces[-length(pieces)]
}
split_words <- function(text) {
  words <- strsplit(text, "[ \t]+")[[1L]]
  words[nzchar(words)]
}
collapse_whitespace <- function(text) paste(split_words(text), collapse = " ")
strip_whitespace <- function(text) sub("[ \t]+$", "", sub("^[ \t]+", "", text))
strip_trailing <- function(text) sub("[ \t]+$", "", text)

header_value <- function(header, name) {
  name <- ascii_lower(name)
  for (field in header$fields) if (field$name == name) return(field$value)
  NULL
}
header_count <- function(header, name) sum(vapply(header$fields, function(field) field$name == ascii_lower(name), logical(1)))

parse_fields <- function(lines) {
  fields <- list()
  invalid <- integer()
  in_field <- FALSE
  for (line in lines) {
    text <- line$text
    if (nchar(text) > 0L && substr(text, 1L, 1L) %in% c(" ", "\t")) {
      if (in_field) {
        last <- length(fields)
        fields[[last]]$value <- paste0(fields[[last]]$value, text)
      } else invalid <- c(invalid, line$number)
      next
    }
    colon <- regexpr(":", text, fixed = TRUE)[1L]
    name <- if (colon > 0L) substr(text, 1L, colon - 1L) else ""
    codes <- utf8ToInt(name)
    in_field <- colon > 1L && all(codes >= 33L & codes <= 126L)
    if (in_field) {
      fields[[length(fields) + 1L]] <- list(name = ascii_lower(name), value = substring(text, colon + 1L))
    } else invalid <- c(invalid, line$number)
  }
  for (i in seq_along(fields)) fields[[i]]$value <- strip_whitespace(fields[[i]]$value)
  list(fields = fields, invalid = invalid)
}

remove_comments <- function(text) {
  output <- character()
  depth <- 0L
  position <- 1L
  while (position <= nchar(text)) {
    char <- substr(text, position, position)
    if (depth == 0L) {
      if (char == "(") {
        depth <- 1L
        output <- c(output, " ")
      } else output <- c(output, char)
    } else if (char == "\\") {
      position <- position + 1L
    } else if (char == "(") {
      depth <- depth + 1L
    } else if (char == ")") depth <- depth - 1L
    position <- position + 1L
  }
  if (depth != 0L) return(NULL)
  paste0(output, collapse = "")
}

tokenize <- function(text, mime = FALSE) {
  specials <- chars(if (mime) "/;=" else "<>:;@,.")
  address_words <- chars("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$%&'*+-/=?^_`{|}~")
  excluded <- chars("()<>@,;:\\\"/[]?=")
  is_word <- function(char) {
    if (!mime) return(char %in% address_words)
    code <- utf8ToInt(char)
    code >= 33L && code <= 126L && !(char %in% excluded)
  }
  tokens <- list()
  position <- 1L
  spaced <- FALSE
  while (position <= nchar(text)) {
    char <- substr(text, position, position)
    if (char %in% c(" ", "\t")) {
      spaced <- TRUE
      position <- position + 1L
      next
    }
    if (char == "(") {
      depth <- 1L
      position <- position + 1L
      while (position <= nchar(text) && depth > 0L) {
        char <- substr(text, position, position)
        if (char == "\\") {
          position <- position + 2L
          next
        }
        if (char == "(") depth <- depth + 1L
        if (char == ")") depth <- depth - 1L
        position <- position + 1L
      }
      if (depth != 0L) return(NULL)
      spaced <- TRUE
      next
    }
    if (char == '"') {
      value <- character()
      position <- position + 1L
      closed <- FALSE
      while (position <= nchar(text)) {
        char <- substr(text, position, position)
        position <- position + 1L
        if (char == '"') {
          closed <- TRUE
          break
        }
        if (char == "\\") {
          if (position > nchar(text)) return(NULL)
          char <- substr(text, position, position)
          position <- position + 1L
        }
        value <- c(value, char)
      }
      if (!closed) return(NULL)
      token <- list(kind = "quoted", text = paste0(value, collapse = ""), spaced = spaced)
    } else if (char %in% specials) {
      token <- list(kind = char, text = char, spaced = spaced)
      position <- position + 1L
    } else if (is_word(char)) {
      end <- position + 1L
      while (end <= nchar(text) && is_word(substr(text, end, end))) end <- end + 1L
      token <- list(kind = "word", text = substr(text, position, end - 1L), spaced = spaced)
      position <- end
    } else return(NULL)
    tokens[[length(tokens) + 1L]] <- token
    spaced <- FALSE
  }
  tokens
}

decode_word <- function(word) {
  unchanged <- function(error = FALSE) list(text = word, decoded = FALSE, error = error)
  if (nchar(word) < 4L || !startsWith(word, "=?") || !endsWith(word, "?=")) return(unchanged())
  inside <- substr(word, 3L, nchar(word) - 2L)
  pieces <- strsplit(paste0(inside, "?X"), "?", fixed = TRUE)[[1L]]
  pieces <- pieces[-length(pieces)]
  if (length(pieces) != 3L || any(!nzchar(pieces))) return(unchanged())
  if (ascii_lower(pieces[1L]) != "us-ascii") return(unchanged(TRUE))
  data <- NULL
  if (pieces[2L] %in% c("B", "b")) {
    data <- strict_base64(pieces[3L])
  } else if (pieces[2L] %in% c("Q", "q")) {
    data <- integer()
    position <- 1L
    while (position <= nchar(pieces[3L])) {
      char <- substr(pieces[3L], position, position)
      if (char == "_") {
        data <- c(data, 32L)
        position <- position + 1L
      } else if (char == "=") {
        value <- escaped_byte(pieces[3L], position)
        if (is.null(value)) return(unchanged(TRUE))
        data <- c(data, value)
        position <- position + 3L
      } else {
        data <- c(data, utf8ToInt(char))
        position <- position + 1L
      }
    }
  }
  if (is.null(data) || any(data < 32L | data > 126L)) return(unchanged(TRUE))
  list(text = intToUtf8(data), decoded = TRUE, error = FALSE)
}

decode_unstructured <- function(value) {
  output <- character()
  previous <- FALSE
  error <- FALSE
  words <- split_words(value)
  for (i in seq_along(words)) {
    decoded <- decode_word(words[i])
    if (i > 1L && !(decoded$decoded && previous)) output <- c(output, " ")
    output <- c(output, decoded$text)
    previous <- decoded$decoded
    error <- error || decoded$error
  }
  list(text = collapse_whitespace(paste0(output, collapse = "")), error = error)
}

parse_parameters <- function(value, with_subtype) {
  tokens <- tokenize(value, TRUE)
  if (is.null(tokens) || length(tokens) == 0L || tokens[[1L]]$kind != "word") return(NULL)
  main_type <- ascii_lower(tokens[[1L]]$text)
  subtype <- ""
  position <- 2L
  if (with_subtype) {
    if (length(tokens) < 3L || tokens[[2L]]$kind != "/" || tokens[[3L]]$kind != "word") return(NULL)
    subtype <- ascii_lower(tokens[[3L]]$text)
    position <- 4L
  }
  parameters <- list()
  while (position <= length(tokens)) {
    if (position + 3L > length(tokens) || tokens[[position]]$kind != ";" ||
        tokens[[position + 1L]]$kind != "word" || tokens[[position + 2L]]$kind != "=" ||
        !(tokens[[position + 3L]]$kind %in% c("word", "quoted"))) return(NULL)
    name <- ascii_lower(tokens[[position + 1L]]$text)
    if (is.null(parameters[[name]])) parameters[[name]] <- tokens[[position + 3L]]$text
    position <- position + 4L
  }
  list(main_type = main_type, subtype = subtype, parameters = parameters)
}
