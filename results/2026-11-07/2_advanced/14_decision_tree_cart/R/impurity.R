statistics <- function(rows, classes) {
  labels <- vapply(rows, function(row) row$label, integer(1L))
  counts <- as.numeric(tabulate(labels, nbins = classes))
  selected <- which.max(counts)
  list(size = as.numeric(length(rows)), counts = counts, squares = sum(counts * counts),
       majority = selected, errors = length(rows) - counts[selected])
}

majority <- function(counts) which.max(counts)

compare_fractions <- function(first, second) {
  left <- first[1L] * second[2L]
  right <- second[1L] * first[2L]
  if (left < right) -1L else if (left > right) 1L else 0L
}

quality <- function(left, right) {
  c(left$squares * right$size + right$squares * left$size, left$size * right$size)
}

improves <- function(value, parent) value[1L] * parent$size > parent$squares * value[2L]

impurity_decrease <- function(parent, left, right) {
  first <- left$squares / left$size
  second <- right$squares / right$size
  before <- parent$squares / parent$size
  (first + second) - before
}
