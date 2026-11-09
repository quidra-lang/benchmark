fp_node <- function(item = "", parent = NULL) {
  node <- new.env(parent = emptyenv())
  node$item <- item
  node$parent <- parent
  node$count <- 0
  node$children <- new.env(hash = TRUE, parent = emptyenv())
  node
}

fp_tree <- function(base, minimum) {
  counts <- numeric()
  for (pair in base) for (item in pair$items) {
    counts[item] <- if (item %in% names(counts)) counts[item] + pair$weight else pair$weight
  }
  frequent <- names(counts)[counts >= minimum]
  header <- frequent[order(-counts[frequent], frequent, method = "radix")]
  root <- fp_node()
  links <- setNames(vector("list", length(header)), header)
  nodes <- 0L
  for (pair in base) {
    node <- root
    for (item in header[header %in% pair$items]) {
      child <- node$children[[item]]
      if (is.null(child)) {
        child <- fp_node(item, node)
        node$children[[item]] <- child
        links[[item]][[length(links[[item]]) + 1L]] <- child
        nodes <- nodes + 1L
      }
      child$count <- child$count + pair$weight
      node <- child
    }
  }
  list(header = header, root = root, links = links, nodes = nodes)
}

conditional_base <- function(tree, item) lapply(tree$links[[item]], function(node) {
  path <- character()
  ancestor <- node$parent
  while (!is.null(ancestor$parent)) {
    path <- c(ancestor$item, path)
    ancestor <- ancestor$parent
  }
  list(items = path, weight = node$count)
})

fp_growth <- function(base, minimum, max_size) {
  tree <- fp_tree(base, minimum)
  result <- list(header = length(tree$header), nodes = tree$nodes, conditional_trees = 0L, conditional_nodes = 0L, supports = numeric())
  stack <- list(list(tree = tree, suffix = character()))
  while (length(stack)) {
    current <- stack[[length(stack)]]
    stack <- head(stack, -1L)
    for (item in rev(current$tree$header)) {
      itemset <- sort(c(current$suffix, item), method = "radix")
      result$supports[itemset_text(itemset)] <- sum(vapply(current$tree$links[[item]], function(node) node$count, numeric(1L)))
      if (length(itemset) < max_size) {
        conditional <- fp_tree(conditional_base(current$tree, item), minimum)
        if (conditional$nodes) {
          stack[[length(stack) + 1L]] <- list(tree = conditional, suffix = itemset)
          result$conditional_trees <- result$conditional_trees + 1L
          result$conditional_nodes <- result$conditional_nodes + conditional$nodes
        }
      }
    }
  }
  result
}
