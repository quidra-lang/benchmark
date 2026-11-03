insert_node <- function(node, value) {
  if (is.null(node)) {
    return(list(value = value, left = NULL, right = NULL))
  }
  if (value < node$value) {
    node$left <- insert_node(node$left, value)
  } else {
    node$right <- insert_node(node$right, value)
  }
  node
}

delete_node <- function(node, value) {
  if (is.null(node)) {
    return(NULL)
  }
  if (value < node$value) {
    node$left <- delete_node(node$left, value)
  } else if (value > node$value) {
    node$right <- delete_node(node$right, value)
  } else if (is.null(node$left)) {
    return(node$right)
  } else if (is.null(node$right)) {
    return(node$left)
  } else {
    successor <- node$right
    while (!is.null(successor$left)) successor <- successor$left
    node$value <- successor$value
    node$right <- delete_node(node$right, successor$value)
  }
  node
}

traversal <- function(node, mode) {
  if (is.null(node)) {
    return(integer(0))
  }
  left <- traversal(node$left, mode)
  right <- traversal(node$right, mode)
  switch(mode,
    inorder = c(left, node$value, right),
    preorder = c(node$value, left, right),
    postorder = c(left, right, node$value)
  )
}

tree_height <- function(node) if (is.null(node)) 0 else 1 + max(tree_height(node$left), tree_height(node$right))

tree <- NULL
for (value in c(50, 27, 74, 13, 39, 62, 88, 6, 31, 45, 70, 34)) tree <- insert_node(tree, value)
for (mode in c("inorder", "preorder", "postorder")) {
  cat(mode, ": ", paste(traversal(tree, mode), collapse = " "), "\n", sep = "")
}
queue <- list(tree)
levelorder <- integer(0)
head_index <- 1
while (head_index <= length(queue)) {
  node <- queue[[head_index]]
  head_index <- head_index + 1
  levelorder <- c(levelorder, node$value)
  if (!is.null(node$left)) queue[[length(queue) + 1]] <- node$left
  if (!is.null(node$right)) queue[[length(queue) + 1]] <- node$right
}
cat(sprintf("levelorder: %s\nheight: %d\n", paste(levelorder, collapse = " "), tree_height(tree)))
tree <- delete_node(tree, 6)
tree <- delete_node(tree, 27)
cat(sprintf(
  "preorder after deletions: %s\nheight after deletions: %d\n",
  paste(traversal(tree, "preorder"), collapse = " "), tree_height(tree)
))
