is_letter <- function(code) {
  (code >= 65L & code <= 90L) | (code >= 97L & code <= 122L)
}

letter_values <- function(text) {
  codes <- utf8ToInt(text)
  codes[is_letter(codes)] %% 32L - 1L
}

letter_string <- function(text) {
  intToUtf8(letter_values(text) + 65L)
}

parse_weights <- function(lines) {
  list(
    monograms = as.integer(strsplit(lines[2L], " ", fixed = TRUE)[[1L]]),
    bigrams = as.integer(unlist(strsplit(lines[4L:29L], " ", fixed = TRUE),
                               use.names = FALSE))
  )
}

monogram_fitness <- function(text, weights) {
  sum(weights$monograms[letter_values(text) + 1L])
}

bigram_fitness <- function(text, weights) {
  values <- letter_values(text)
  if (length(values) < 2L) return(0L)
  indices <- 26L * head(values, -1L) + tail(values, -1L) + 1L
  sum(weights$bigrams[indices])
}
