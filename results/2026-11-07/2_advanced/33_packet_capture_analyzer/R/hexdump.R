new_object <- function(...) list2env(list(...), parent = emptyenv())
new_packet <- function(number, time, size) {
  new_object(number = number, time = time, length = size, data = integer(),
             error = NULL, layers = character(), fields = list(), remaining = integer())
}
field_values <- function(object, name) {
  value <- object$fields[[name]]
  if (is.null(value)) list() else value
}
packet_value <- function(object, name) {
  values <- field_values(object, name)
  if (length(values)) values[[1L]] else NULL
}
field_exists <- function(object, name) !is.null(object$fields[[name]])
set_field <- function(object, name, value) object$fields[[name]] <- list(value)
add_field <- function(object, name, value) {
  object$fields[[name]] <- c(field_values(object, name), list(value))
}
read_capture <- function(path) {
  packets <- list()
  dumps <- list()
  lines <- readLines(path, warn = FALSE)
  for (number in seq_along(lines)) {
    line <- lines[[number]]
    if (startsWith(line, "PACKET ")) {
      header <- as.numeric(strsplit(line, " ", fixed = TRUE)[[1L]][2L:4L])
      packets[[length(packets) + 1L]] <- new_packet(header[[1L]], header[[2L]], header[[3L]])
      dumps[[length(packets)]] <- list()
    } else if (nzchar(line)) {
      index <- length(packets)
      dumps[[index]][[length(dumps[[index]]) + 1L]] <- list(number, line)
    }
  }
  for (index in seq_along(packets)) {
    packet <- packets[[index]]
    bytes <- integer()
    for (entry in dumps[[index]]) {
      number <- entry[[1L]]
      line <- entry[[2L]]
      if (!grepl("^[0-9a-f]{4}  [0-9a-f]{2}( [0-9a-f]{2}){0,15}$", line)) {
        packet$error <- paste("dump: bad line", number)
        break
      }
      if (strtoi(substr(line, 1L, 4L), base = 16L) != length(bytes)) {
        packet$error <- paste("dump: offset mismatch at line", number)
        break
      }
      bytes <- c(bytes, strtoi(strsplit(substring(line, 7L), " ", fixed = TRUE)[[1L]], base = 16L))
    }
    if (is.null(packet$error)) {
      if (length(bytes) != packet$length) {
        packet$error <- sprintf("dump: length mismatch (header %.0f, data %d)", packet$length, length(bytes))
      } else packet$data <- bytes
    }
  }
  packets
}
hex_dump_lines <- function(data) {
  lines <- character()
  if (!length(data)) return(lines)
  for (offset in seq.int(0L, length(data) - 1L, by = 16L)) {
    piece <- data[seq.int(offset + 1L, min(offset + 16L, length(data)))]
    bytes <- paste(sprintf("%02x", piece), collapse = " ")
    text <- paste(
        vapply(piece, function(byte) if (byte >= 32L && byte <= 126L) intToUtf8(byte) else ".", ""),
        collapse = ""
    )
    lines <- c(lines, sprintf("%04x  %-47s  |%s|", offset, bytes, text))
  }
  lines
}
