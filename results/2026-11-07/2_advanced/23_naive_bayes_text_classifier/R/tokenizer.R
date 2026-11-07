tokenize <- function(text, stopwords) {
  text <- chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", text)
  words <- regmatches(text, gregexpr("[a-z0-9]+", text))[[1L]]
  kept <- character()
  stop_count <- short_count <- 0L
  for (word in words) {
    if (word %in% stopwords) {
      stop_count <- stop_count + 1L
    } else if (nchar(word) == 1L) {
      short_count <- short_count + 1L
    } else kept <- c(kept, word)
  }
  bigrams <- if (length(kept) > 1L) paste0(head(kept, -1L), "_", tail(kept, -1L)) else character()
  list(raw = length(words), stopwords = stop_count, short = short_count, words = kept, bigrams = bigrams, bigram_terms = c(kept, bigrams))
}
term_sequence <- function(tokens, bigrams) if (bigrams) tokens$bigram_terms else tokens$words
is_bigram <- function(term) grepl("_", term, fixed = TRUE)
