tree_view <- function(root, cuts = numeric()) list(root = root, cuts = cuts)
is_leaf <- function(node, tree) is.null(node$split) || node$number %in% tree$cuts

preorder <- function(tree, start = tree$root) {
  nodes <- list()
  pending <- list(start)
  while (length(pending)) {
    node <- pending[[length(pending)]]
    pending <- pending[-length(pending)]
    nodes[[length(nodes) + 1L]] <- node
    if (!is_leaf(node, tree)) pending <- c(pending, list(node$right, node$left))
  }
  nodes
}

leaves <- function(tree) Filter(function(node) is_leaf(node, tree), preorder(tree))
internal_nodes <- function(tree) Filter(function(node) !is_leaf(node, tree), preorder(tree))
tree_depth <- function(tree) max(vapply(leaves(tree), function(node) node$depth, numeric(1L)))
training_errors <- function(tree) sum(vapply(leaves(tree), function(node) node$stats$errors, numeric(1L)))

route <- function(tree, row) {
  node <- tree$root
  path <- list()
  steps <- list()
  repeat {
    path[[length(path) + 1L]] <- node
    if (is_leaf(node, tree)) return(list(leaf = node, path = path, steps = steps))
    left <- node$default_left
    method <- "default"
    if (!is.na(row$values[node$split$attribute$index])) {
      left <- goes_left(node$split, row)
      method <- "primary"
    } else {
      for (surrogate in node$surrogates) {
        if (is.na(row$values[surrogate$split$attribute$index])) next
        left <- goes_left(surrogate$split, row) == surrogate$left
        method <- "surrogate"
        break
      }
    }
    steps[[length(steps) + 1L]] <- list(node = node, left = left, method = method)
    node <- if (left) node$left else node$right
  }
}

predict_tree <- function(tree, row) route(tree, row)$leaf$stats$majority
correct_count <- function(tree, rows) sum(vapply(rows, function(row) predict_tree(tree, row) == row$label, logical(1L)))
integer_text <- function(value) sprintf("%.0f", value)

real_text <- function(value, places = 4L) {
  text <- sprintf(paste0("%.", places, "f"), value)
  if (startsWith(text, "-") && as.numeric(text) == 0) substring(text, 2L) else text
}

ratio_text <- function(numerator, denominator) {
  if (denominator == 0) return("0/0 -")
  paste0(integer_text(numerator), "/", integer_text(denominator), " ", real_text(numerator / denominator))
}

fraction_text <- function(numerator, denominator, places = 4L) {
  if (denominator == 0) return("- -")
  a <- abs(numerator)
  b <- denominator
  while (b != 0) {
    remainder <- a %% b
    a <- b
    b <- remainder
  }
  paste0(integer_text(numerator / a), "/", integer_text(denominator / a), " ", real_text(numerator / denominator, places))
}

classification_lines <- function(title, classes, rows, predicted) {
  matrix <- matrix(0, nrow = length(classes), ncol = length(classes))
  correct <- 0
  for (index in seq_along(rows)) {
    label <- rows[[index]]$label
    matrix[label, predicted[index]] <- matrix[label, predicted[index]] + 1
    if (label == predicted[index]) correct <- correct + 1
  }
  lines <- c(paste("confusion", title, "correct", paste0(correct, "/", length(rows)), "accuracy", fraction_text(correct, length(rows))),
             paste("actual\\predicted", paste(classes, collapse = " ")))
  for (index in seq_along(classes)) lines <- c(lines, paste(classes[index], paste(matrix[index, ], collapse = " ")))
  macro <- 0
  defined <- 0
  for (index in seq_along(classes)) {
    hits <- matrix[index, index]
    predicted_total <- sum(matrix[, index])
    support <- sum(matrix[index, ])
    denominator <- predicted_total + support
    if (denominator > 0) {
      macro <- macro + 2 * hits / denominator
      defined <- defined + 1
    }
    lines <- c(lines, paste("class", classes[index], "precision", fraction_text(hits, predicted_total),
                            "recall", fraction_text(hits, support), "f1", fraction_text(2 * hits, denominator), "support", support))
  }
  c(lines, paste("macro_f1", if (defined == 0) "-" else real_text(macro / defined)))
}
