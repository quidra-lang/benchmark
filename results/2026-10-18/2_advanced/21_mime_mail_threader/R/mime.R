base64_alphabet <- strsplit("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/", "", fixed = TRUE)[[1L]]

strict_base64 <- function(text) {
  if (nchar(text) %% 4 != 0) return(NULL)
  data <- sub("=+$", "", text)
  if (nchar(text) - nchar(data) >= 3L) return(NULL)
  result <- integer()
  buffer <- bits <- 0
  for (char in strsplit(data, "", fixed = TRUE)[[1L]]) {
    value <- match(char, base64_alphabet) - 1L
    if (is.na(value)) return(NULL)
    buffer <- buffer * 64 + value
    bits <- bits + 6L
    if (bits >= 8L) {
      bits <- bits - 8L
      result <- c(result, buffer %/% (2 ^ bits))
      buffer <- buffer %% (2 ^ bits)
    }
  }
  result
}

hex_value <- function(char) {
  value <- utf8ToInt(char)
  if (value >= 48L && value <= 57L) return(value - 48L)
  if (value >= 65L && value <= 70L) return(value - 55L)
  if (value >= 97L && value <= 102L) return(value - 87L)
  -1L
}

escaped_byte <- function(text, position) {
  if (position + 2L > nchar(text)) return(NULL)
  a <- hex_value(substr(text, position + 1L, position + 1L))
  b <- hex_value(substr(text, position + 2L, position + 2L))
  if (a < 0L || b < 0L) return(NULL)
  a * 16L + b
}

decode_base64_body <- function(text) {
  data <- strict_base64(gsub("[ \t\n]", "", text))
  if (is.null(data)) return(NULL)
  converted <- integer()
  position <- 1L
  while (position <= length(data)) {
    if (data[position] == 13L && position < length(data) && data[position + 1L] == 10L) {
      converted <- c(converted, 10L)
      position <- position + 2L
    } else {
      converted <- c(converted, data[position])
      position <- position + 1L
    }
  }
  if (any(!(converted %in% c(9L, 10L)) & (converted < 32L | converted > 126L))) return(NULL)
  intToUtf8(converted)
}

decode_quoted_printable <- function(text) {
  output <- character()
  error <- FALSE
  lines <- split_lf(text)
  for (i in seq_along(lines)) {
    line <- strip_trailing(lines[i])
    soft <- endsWith(line, "=")
    if (soft) line <- substr(line, 1L, nchar(line) - 1L)
    position <- 1L
    while (position <= nchar(line)) {
      char <- substr(line, position, position)
      decoded <- if (char == "=") escaped_byte(line, position) else NULL
      if (!is.null(decoded) && (decoded == 9L || decoded >= 32L && decoded <= 126L)) {
        output <- c(output, intToUtf8(decoded))
        position <- position + 3L
      } else {
        output <- c(output, char)
        error <- error || char == "="
        position <- position + 1L
      }
    }
    if (!soft && i < length(lines)) output <- c(output, "\n")
  }
  list(text = paste0(output, collapse = ""), error = error)
}
