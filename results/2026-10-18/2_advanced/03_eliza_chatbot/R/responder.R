reflect_words <- function(words, reflections) {
  unlist(lapply(words, function(word) {
    replacement <- reflections[[word]]
    if (is.null(replacement)) word else replacement
  }), use.names = FALSE)
}

binding <- function(bindings, number) {
  if (number >= 1L && number <= length(bindings)) bindings[[number]] else character()
}

build_reply <- function(template, bindings, reflections) {
  pieces <- character()
  position <- 1L
  while (position <= nchar(template)) {
    chunk <- substr(template, position, position + 2L)
    if (is_reference(chunk)) {
      number <- as.integer(substr(chunk, 2L, 2L))
      pieces <- c(pieces, paste(reflect_words(binding(bindings, number), reflections), collapse = " "))
      position <- position + 3L
    } else {
      pieces <- c(pieces, substr(template, position, position))
      position <- position + 1L
    }
  }
  reply <- paste(words_of(paste(pieces, collapse = "")), collapse = " ")
  if (nchar(reply)) substr(reply, 1L, 1L) <- toupper(substr(reply, 1L, 1L))
  reply
}

restated_words <- function(args, bindings) {
  unlist(lapply(args, function(arg) {
    if (is_reference(arg)) binding(bindings, as.integer(substr(arg, 2L, 2L))) else arg
  }), use.names = FALSE)
}

eliza_lines <- function(text) {
  words <- words_of(text)
  lines <- paste0("ELIZA: ", words[1L])
  for (word in words[-1L]) {
    last <- length(lines)
    if (nchar(lines[last]) + 1L + nchar(word) <= 72L) lines[last] <- paste(lines[last], word)
    else lines <- c(lines, paste0("       ", word))
  }
  lines
}
