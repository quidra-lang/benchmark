reduced_error_pruning <- function(root, validation) {
  original <- tree_view(root)
  maximum <- max(vapply(preorder(original), function(node) node$number, numeric(1L)))
  visits <- numeric(maximum)
  errors <- numeric(maximum)
  for (row in validation) {
    for (node in route(original, row)$path) {
      visits[node$number] <- visits[node$number] + 1
      errors[node$number] <- errors[node$number] + as.numeric(row$label != node$stats$majority)
    }
  }
  cuts <- numeric()
  decisions <- list()
  decide <- function(node) {
    leaf_error <- errors[node$number]
    if (is.null(node$split)) return(leaf_error)
    subtree_error <- decide(node$left) + decide(node$right)
    pruned <- leaf_error <= subtree_error
    decisions[[length(decisions) + 1L]] <<- list(node = node, rows = visits[node$number],
        leaf_error = leaf_error, subtree_error = subtree_error, pruned = pruned)
    if (pruned) {
      cuts <<- c(cuts, node$number)
      leaf_error
    } else subtree_error
  }
  decide(root)
  list(tree = tree_view(root, cuts), decisions = decisions)
}

cost_complexity_sequence <- function(root) {
  tree <- tree_view(root)
  sequence <- list(list(alpha = c(0, 1), tree = tree))
  while (!is_leaf(root, tree)) {
    alpha <- NULL
    weakest <- numeric()
    for (node in internal_nodes(tree)) {
      descendants <- Filter(function(item) is_leaf(item, tree), preorder(tree, node))
      errors <- sum(vapply(descendants, function(item) item$stats$errors, numeric(1L)))
      strength <- c(node$stats$errors - errors, length(descendants) - 1)
      comparison <- if (is.null(alpha)) -1L else compare_fractions(strength, alpha)
      if (comparison < 0L) {
        alpha <- strength
        weakest <- node$number
      } else if (comparison == 0L) weakest <- c(weakest, node$number)
    }
    tree <- tree_view(root, unique(c(tree$cuts, weakest)))
    sequence[[length(sequence) + 1L]] <- list(alpha = alpha, tree = tree)
  }
  sequence
}
