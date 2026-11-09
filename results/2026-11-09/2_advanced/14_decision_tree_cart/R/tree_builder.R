half_text <- function(point) sprintf("%.0f.%d", point %/% 2, as.integer(5 * (point %% 2)))

goes_left <- function(split, row) {
  value <- row$values[split$attribute$index]
  if (split$attribute$integer) 2 * value <= split$point else value == split$point
}

split_text <- function(split, left) {
  attribute <- split$attribute
  if (attribute$integer) paste(attribute$name, if (left) "<=" else ">", half_text(split$point))
  else paste(attribute$name, if (left) "=" else "!=", attribute$values[split$point])
}

split_candidates <- function(rows, attribute) {
  values <- sort(unique(vapply(rows, function(row) row$values[attribute$index], numeric(1L))), method = "radix")
  if (length(values) < 2L) return(list())
  points <- if (attribute$integer) values[-length(values)] + values[-1L] else values
  lapply(points, function(point) list(attribute = attribute, point = point))
}

best_for_attribute <- function(rows, attribute, classes, settings) {
  best <- NULL
  for (split in split_candidates(rows, attribute)) {
    selected <- vapply(rows, function(row) goes_left(split, row), logical(1L))
    left <- rows[selected]
    right <- rows[!selected]
    if (length(left) < settings$min_samples_leaf || length(right) < settings$min_samples_leaf) next
    value <- quality(statistics(left, classes), statistics(right, classes))
    if (is.null(best) || compare_fractions(value, best$value) > 0L) {
      best <- list(split = split, left = left, right = right, value = value)
    }
  }
  best
}

best_split <- function(rows, attributes, classes, settings) {
  best <- NULL
  for (attribute in attributes) {
    candidate <- best_for_attribute(rows, attribute, classes, settings)
    if (!is.null(candidate) && (is.null(best) || compare_fractions(candidate$value, best$value) > 0L)) best <- candidate
  }
  best
}

find_surrogates <- function(rows, primary, attributes, limit, left_count, right_count) {
  retained <- list()
  primary_left <- vapply(rows, function(row) goes_left(primary, row), logical(1L))
  for (attribute in attributes) {
    if (attribute$index == primary$attribute$index) next
    best <- NULL
    for (split in split_candidates(rows, attribute)) {
      agreement <- sum(vapply(rows, function(row) goes_left(split, row), logical(1L)) == primary_left)
      left <- agreement >= length(rows) - agreement
      score <- max(agreement, length(rows) - agreement)
      if (is.null(best) || score > best$score) best <- list(split = split, left = left, score = score)
    }
    if (!is.null(best) && best$score > max(left_count, right_count)) retained[[length(retained) + 1L]] <- best
  }
  if (!length(retained) || limit == 0) return(list())
  scores <- vapply(retained, function(item) item$score, numeric(1L))
  indices <- vapply(retained, function(item) item$split$attribute$index, integer(1L))
  retained[head(order(-scores, indices, method = "radix"), limit)]
}

grow_tree <- function(rows, attributes, classes, settings) {
  grow <- function(sequence, number, depth) {
    stats <- statistics(sequence, classes)
    node <- list(number = number, depth = depth, stats = stats, split = NULL,
                 surrogates = list(), default_left = TRUE, left = NULL, right = NULL)
    if (stats$errors == 0 || depth == settings$max_depth || length(sequence) < settings$min_samples_split) return(node)
    best <- best_split(sequence, attributes, classes, settings)
    if (is.null(best) || !improves(best$value, stats)) return(node)
    node$split <- best$split
    node$default_left <- length(best$left) >= length(best$right)
    node$surrogates <- find_surrogates(sequence, best$split, attributes, settings$max_surrogates, length(best$left), length(best$right))
    node$left <- grow(best$left, 2 * number, depth + 1)
    node$right <- grow(best$right, 2 * number + 1, depth + 1)
    node
  }
  grow(rows, 1, 0)
}
