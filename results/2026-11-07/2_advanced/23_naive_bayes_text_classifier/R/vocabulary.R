first_occurrences <- function(sequence) unique(sequence)
chi_square <- function(with_term, frequency, class_size, total) {
  b <- frequency - with_term
  c <- class_size - with_term
  e <- total - class_size - b
  difference <- with_term * e - b * c
  numerator <- total * difference * difference
  denominator <- frequency * (total - frequency) * class_size * (total - class_size)
  if (denominator == 0) 0 else numerator / denominator
}
build_vocabulary <- function(sequences, labels, class_count, min_df, size) {
  counts <- new.env(hash = TRUE, parent = emptyenv())
  class_sizes <- numeric(class_count)
  for (i in seq_along(sequences)) {
    label <- labels[i]
    class_sizes[label] <- class_sizes[label] + 1
    for (term in unique(sequences[[i]])) {
      row <- if (exists(term, envir = counts, inherits = FALSE)) get(term, envir = counts) else numeric(class_count)
      row[label] <- row[label] + 1
      assign(term, row, envir = counts)
    }
  }
  terms <- sort(ls(counts, all.names = TRUE), method = "radix")
  ranking <- list()
  for (term in terms) {
    row <- get(term, envir = counts)
    frequency <- sum(row)
    if (frequency < min_df) next
    best_class <- 1L
    best_score <- chi_square(row[1L], frequency, class_sizes[1L], length(sequences))
    for (label in seq.int(2L, class_count)) {
      score <- chi_square(row[label], frequency, class_sizes[label], length(sequences))
      if (score > best_score) {
        best_class <- label
        best_score <- score
      }
    }
    ranking[[length(ranking) + 1L]] <- list(term = term, frequency = frequency, score = best_score, best_class = best_class)
  }
  candidate_count <- length(ranking)
  if (candidate_count > 0L) ranking <- ranking[order(-vapply(ranking, function(entry) entry$score, numeric(1)), vapply(ranking, function(entry) entry$term, character(1)), method = "radix")]
  if (size > 0L && length(ranking) > size) ranking <- head(ranking, size)
  selected <- sort(vapply(ranking, function(entry) entry$term, character(1)), method = "radix")
  frequencies <- setNames(vapply(ranking, function(entry) entry$frequency, numeric(1)), vapply(ranking, function(entry) entry$term, character(1)))
  list(term_count = length(terms), candidate_count = candidate_count, ranking = ranking, terms = selected,
       index = setNames(seq_along(selected), selected), frequencies = unname(frequencies[selected]))
}
encode <- function(vocabulary, sequence) {
  positions <- unname(vocabulary$index[sequence])
  positions[!is.na(positions)]
}
