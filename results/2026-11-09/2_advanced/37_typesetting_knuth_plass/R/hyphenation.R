is_letter <- function(character) grepl("^[A-Za-z]$", character)
new_hyphenation <- function(lines, additions, left_min, right_min) {
  words <- new.env(hash = TRUE, parent = emptyenv())
  for (spelling in c(lines, additions)) {
    parts <- split_all(spelling, "-")
    points <- head(cumsum(nchar(parts)), -1L)
    words[[paste(parts, collapse = "")]] <- as.integer(points)
  }
  list(words = words, left_min = left_min, right_min = right_min)
}
split_points <- function(dictionary, word) {
  points <- list()
  first <- 1L
  last <- nchar(word)
  while (first <= last && !is_letter(substr(word, first, first))) first <- first + 1L
  while (last >= first && !is_letter(substr(word, last, last))) last <- last - 1L
  core <- substr(word, first, last)
  if (nzchar(core) && grepl("^[A-Za-z]+$", core)) {
    key <- tolower(core)
    if (exists(key, envir = dictionary$words, inherits = FALSE)) {
      for (position in dictionary$words[[key]]) {
        if (position >= dictionary$left_min && nchar(core) - position >= dictionary$right_min) points[[as.character(first - 1L + position)]] <- TRUE
      }
    }
  }
  if (nchar(word) >= 3L) {
    for (position in seq.int(2L, nchar(word) - 1L)) {
      if (substr(word, position, position) == "-" && is_letter(substr(word, position - 1L, position - 1L)) && is_letter(substr(
          word,
          position + 1L,
          position + 1L
      ))) points[[as.character(position)]] <- FALSE
    }
  }
  if (!length(points)) return(list())
  indices <- sort(as.integer(names(points)))
  lapply(indices, function(index) list(position = index, append = points[[as.character(index)]]))
}
