letter_counts <- function(text) {
  tabulate(letter_values(text) + 1L, nbins = 26L)
}

index_of_coincidence <- function(text) {
  counts <- letter_counts(text)
  total <- sum(counts * (counts - 1L))
  length <- nchar(text)
  denominator <- length * (length - 1L)
  quotient <- total %/% denominator
  remainder <- total %% denominator
  for (i in seq_len(5L)) {
    remainder <- 10L * remainder
    quotient <- 10L * quotient + remainder %/% denominator
    remainder <- remainder %% denominator
  }
  quotient
}

period_columns <- function(text, period) {
  codes <- utf8ToInt(text)
  lapply(seq_len(period), function(column) {
    intToUtf8(codes[seq.int(column, length(codes), by = period)])
  })
}

column_indices <- function(text, period) {
  vapply(period_columns(text, period), index_of_coincidence, integer(1L))
}

integer_gcd <- function(a, b) {
  while (b != 0L) {
    remainder <- a %% b
    a <- b
    b <- remainder
  }
  a
}

repeated_trigrams <- function(text) {
  starts <- seq_len(max(0L, nchar(text) - 2L))
  if (!length(starts)) return(list())
  trigrams <- substring(text, starts, starts + 2L)
  groups <- split(starts, trigrams)
  groups <- groups[lengths(groups) >= 2L]
  groups <- groups[order(names(groups), method = "radix")]
  lapply(seq_along(groups), function(i) {
    positions <- groups[[i]]
    gaps <- diff(positions)
    list(trigram = names(groups)[i], positions = positions, gaps = gaps,
         gcd = Reduce(integer_gcd, gaps))
  })
}

percentage <- function(count, total) {
  tenths <- (2000L * count + total) %/% (2L * total)
  paste0(tenths %/% 10L, ".", tenths %% 10L)
}

top_counts <- function(items, limit = 10L) {
  keys <- sort(unique(items), method = "radix")
  counts <- tabulate(match(items, keys), nbins = length(keys))
  ranked <- order(-counts, seq_along(keys), method = "radix")
  ranked <- head(ranked, limit)
  setNames(counts[ranked], keys[ranked])
}
