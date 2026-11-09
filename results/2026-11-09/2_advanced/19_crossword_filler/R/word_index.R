valid_word <- function(text) nchar(text) >= 3L && nchar(text) <= 15L && grepl("^[A-Z]+$", text)
valid_integer <- function(text, low, high) {
  if (!nzchar(text) || substr(text, 1L, 1L) == "0" || nchar(text) > nchar(as.character(high)) || !grepl("^[0-9]+$", text)) return(FALSE)
  value <- as.integer(text)
  value >= low && value <= high
}

word_line_error <- function(line) {
  spaces <- nchar(line) - nchar(gsub(" ", "", line, fixed = TRUE))
  if (spaces != 1L) return("bad format")
  split <- regexpr(" ", line, fixed = TRUE)[1L]
  word <- substr(line, 1L, split - 1L)
  score <- substring(line, split + 1L)
  if (!valid_word(word)) return("bad word")
  if (valid_integer(score, 1L, 100L)) "" else "bad score"
}

clue_line_error <- function(line) {
  separators <- nchar(line) - nchar(gsub("|", "", line, fixed = TRUE))
  if (separators != 1L) return("bad format")
  split <- regexpr("|", line, fixed = TRUE)[1L]
  word <- substr(line, 1L, split - 1L)
  clue <- substring(line, split + 1L)
  if (!valid_word(word)) return("bad word")
  if (nchar(clue) < 1L || nchar(clue) > 60L || startsWith(clue, " ") || endsWith(clue, " ")) "bad clue" else ""
}

matches <- function(word, pattern) all(pattern == "." | pattern == word)
letter_key <- function(size, position, letter) paste(size, position, letter, sep = ":")

new_word_index <- function(scores) {
  names <- names(scores)
  ranked <- names[order(-scores, names, method = "radix")]
  values <- unname(scores[ranked])
  letters <- strsplit(ranked, "", fixed = TRUE)
  lookup <- new.env(hash = TRUE, parent = emptyenv())
  by_length <- lapply(seq_len(15L), function(i) integer())
  by_letter <- new.env(hash = TRUE, parent = emptyenv())
  for (id in seq_along(ranked)) {
    assign(ranked[id], id, lookup)
    size <- nchar(ranked[id])
    by_length[[size]] <- c(by_length[[size]], id)
    for (position in seq_len(size)) {
      key <- letter_key(size, position, letters[[id]][position])
      assign(key, c(get0(key, by_letter, inherits = FALSE, ifnotfound = integer()), id), by_letter)
    }
  }
  list(words = ranked, scores = values, letters = letters, lookup = lookup, by_length = by_length, by_letter = by_letter)
}

word_id <- function(index, word) get0(word, index$lookup, inherits = FALSE, ifnotfound = 0L)

candidates <- function(index, pattern, minimum, used) {
  size <- length(pattern)
  pool <- index$by_length[[size]]
  for (position in seq_along(pattern)) {
    if (pattern[position] == ".") next
    bucket <- get0(letter_key(size, position, pattern[position]), index$by_letter, inherits = FALSE, ifnotfound = integer())
    if (length(bucket) < length(pool)) pool <- bucket
  }
  result <- integer()
  for (id in pool) {
    if (index$scores[id] < minimum) break
    if (!used[id] && matches(index$letters[[id]], pattern)) result <- c(result, id)
  }
  result
}
