ordered_children <- function(merges, count) {
  minimum <- seq_len(count)
  children <- list()
  for (step in seq_along(merges)) {
    merge <- merges[[step]]
    children[[step]] <- if (minimum[merge$a] < minimum[merge$b]) c(merge$a, merge$b) else c(merge$b, merge$a)
    minimum <- c(minimum, min(minimum[merge$a], minimum[merge$b]))
  }
  children
}
leaf_order <- function(children, count) {
  order <- integer()
  pending <- count + length(children)
  while (length(pending)) {
    node <- tail(pending, 1)
    pending <- head(pending, -1)
    if (node <= count) order <- c(order, node) else pending <- c(pending, rev(children[[node - count]]))
  }
  order
}
column <- function(height, maximum, width) {
  position <- floor(height / maximum * width)
  if (position > width) width + 1 else position
}
dendrogram_rows <- function(merges, children, order, idents, labels, maximum, cut_columns, width) {
  count <- length(order)
  grid <- matrix(0L, count, width + 1)
  mark <- function(row, x, level) grid[row, x + 1] <<- max(grid[row, x + 1], level)
  anchor <- numeric(2 * count - 1)
  anchor[order] <- seq_len(count)
  for (x in cut_columns) if (x <= width) for (row in seq_len(count)) mark(row, x, 1L)
  columns <- vapply(merges, function(merge) column(merge$height, maximum, width), numeric(1))
  for (step in seq_along(children)) {
    upper <- children[[step]][1]
    lower <- children[[step]][2]
    x <- columns[step]
    mark(anchor[upper], x, 4L)
    mark(anchor[lower], x, 4L)
    if (anchor[upper] + 1 < anchor[lower]) for (row in seq.int(anchor[upper] + 1, anchor[lower] - 1)) mark(row, x, 3L)
    for (child in c(upper, lower)) {
      start <- if (child <= count) 0 else columns[child - count] + 1
      if (start < x) for (position in seq.int(start, x - 1)) mark(anchor[child], position, 2L)
    }
    anchor[count + step] <- (anchor[upper] + anchor[lower]) %/% 2
  }
  id_width <- max(nchar(idents))
  label_width <- max(nchar(labels))
  marks <- c(" ", ":", "-", "|", "+")
  rows <- character()
  for (row in seq_len(count)) {
    leaf <- order[row]
    cells <- paste(marks[grid[row, ] + 1], collapse = "")
    text <- paste0(idents[leaf], strrep(" ", id_width - nchar(idents[leaf])), " ", labels[leaf], strrep(" ", label_width - nchar(labels[leaf])), " ", cells)
    rows <- c(rows, sub(" +$", "", text))
  }
  scale <- paste(ifelse((0:width) %% 10 == 0, "+", "-"), collapse = "")
  c(rows, paste0(strrep(" ", id_width + label_width + 2), scale))
}
