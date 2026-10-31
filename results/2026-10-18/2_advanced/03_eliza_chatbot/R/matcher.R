is_wildcard <- function(element) element %in% c("*", "#") | startsWith(element, "@")

word_fits <- function(element, word, groups) {
  if (element == "#") return(TRUE)
  if (startsWith(element, "@")) return(word %in% groups[[substring(element, 2L)]])
  element == word
}

match_pattern <- function(pattern, words, groups) {
  search <- function(position, start, bindings) {
    if (position > length(pattern)) return(if (start > length(words)) bindings else NULL)
    element <- pattern[position]
    if (element == "*") {
      for (end in seq.int(start - 1L, length(words))) {
        bound <- if (end < start) character() else words[seq.int(start, end)]
        found <- search(position + 1L, end + 1L, c(bindings, list(bound)))
        if (!is.null(found)) return(found)
      }
    } else if (start <= length(words) && word_fits(element, words[start], groups)) {
      if (is_wildcard(element)) bindings <- c(bindings, list(words[start]))
      return(search(position + 1L, start + 1L, bindings))
    }
    NULL
  }
  search(1L, 1L, list())
}

element_covers <- function(element, other, groups) {
  if (element == "#") return(other != "*")
  if (startsWith(element, "@")) {
    members <- groups[[substring(element, 2L)]]
    if (startsWith(other, "@")) return(all(groups[[substring(other, 2L)]] %in% members))
    return(other %in% members)
  }
  element == other
}

pattern_covers <- function(earlier, later, groups) {
  search <- function(position, start) {
    if (position > length(earlier)) return(start > length(later))
    if (earlier[position] == "*") {
      for (end in seq.int(start, length(later) + 1L)) if (search(position + 1L, end)) return(TRUE)
    } else if (start <= length(later) && element_covers(earlier[position], later[start], groups)) {
      return(search(position + 1L, start + 1L))
    }
    FALSE
  }
  search(1L, 1L)
}
