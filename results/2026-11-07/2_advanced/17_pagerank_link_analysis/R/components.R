strong_components <- function(adjacency) {
  count <- length(adjacency)
  order <- rep(-1L, count)
  low <- integer(count)
  on_stack <- logical(count)
  stack <- integer()
  components <- list()
  counter <- 0L
  for (root in seq_len(count)) {
    if (order[root] >= 0L) next
    order[root] <- low[root] <- counter
    counter <- counter + 1L
    stack <- c(stack, root)
    on_stack[root] <- TRUE
    work_nodes <- root
    work_positions <- 1L
    while (length(work_nodes)) {
      top <- length(work_nodes)
      node <- work_nodes[top]
      position <- work_positions[top]
      if (position <= length(adjacency[[node]])) {
        work_positions[top] <- position + 1L
        child <- adjacency[[node]][position]
        if (order[child] < 0L) {
          order[child] <- low[child] <- counter
          counter <- counter + 1L
          stack <- c(stack, child)
          on_stack[child] <- TRUE
          work_nodes <- c(work_nodes, child)
          work_positions <- c(work_positions, 1L)
        } else if (on_stack[child]) low[node] <- min(low[node], order[child])
        next
      }
      work_nodes <- work_nodes[-top]
      work_positions <- work_positions[-top]
      if (length(work_nodes)) {
        parent <- tail(work_nodes, 1L)
        low[parent] <- min(low[parent], low[node])
      }
      if (low[node] == order[node]) {
        component <- integer()
        repeat {
          member <- tail(stack, 1L)
          stack <- head(stack, -1L)
          on_stack[member] <- FALSE
          component <- c(component, member)
          if (member == node) break
        }
        components[[length(components) + 1L]] <- component
      }
    }
  }
  components
}

reachable <- function(adjacency, starts) {
  seen <- logical(length(adjacency))
  stack <- integer()
  for (start in starts) {
    if (!seen[start]) { seen[start] <- TRUE; stack <- c(stack, start) }
  }
  while (length(stack)) {
    node <- tail(stack, 1L)
    stack <- head(stack, -1L)
    for (neighbor in adjacency[[node]]) {
      if (!seen[neighbor]) { seen[neighbor] <- TRUE; stack <- c(stack, neighbor) }
    }
  }
  seen
}

bfs_distances <- function(adjacency, sources) {
  distance <- rep(-1L, length(adjacency))
  queue <- integer()
  for (source in sources) {
    if (distance[source] < 0L) { distance[source] <- 0L; queue <- c(queue, source) }
  }
  head <- 1L
  while (head <= length(queue)) {
    node <- queue[head]
    head <- head + 1L
    for (neighbor in adjacency[[node]]) {
      if (distance[neighbor] < 0L) {
        distance[neighbor] <- distance[node] + 1L
        queue <- c(queue, neighbor)
      }
    }
  }
  distance
}

weak_components <- function(neighbors) {
  labels <- rep(-1L, length(neighbors))
  count <- 0L
  for (start in seq_along(neighbors)) {
    if (labels[start] >= 0L) next
    count <- count + 1L
    labels[start] <- count
    stack <- start
    while (length(stack)) {
      node <- tail(stack, 1L)
      stack <- head(stack, -1L)
      for (neighbor in neighbors[[node]]) {
        if (labels[neighbor] < 0L) {
          labels[neighbor] <- count
          stack <- c(stack, neighbor)
        }
      }
    }
  }
  labels
}
