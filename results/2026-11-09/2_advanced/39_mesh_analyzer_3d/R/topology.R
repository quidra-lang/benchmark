triangle_edges <- function(vertices) list(vertices[1L:2L], vertices[2L:3L], vertices[c(3L, 1L)])
key_edge <- function(a, b) paste(min(a, b), max(a, b), sep = ":")
edge_vertices <- function(key) as.integer(strsplit(key, ":", fixed = TRUE)[[1L]])
edge_table <- function(faces) {
  edges <- list()
  for (index in seq_along(faces)) for (edge in triangle_edges(faces[[index]]$vertices)) {
    key <- key_edge(edge[[1L]], edge[[2L]])
    edges[[key]] <- c(edges[[key]], index)
  }
  keys <- names(edges)
  if (!length(keys)) return(edges)
  pairs <- lapply(keys, edge_vertices)
  edges[order(vapply(pairs, `[[`, 0L, 1L), vapply(pairs, `[[`, 0L, 2L), method = "radix")]
}
connected_components <- function(faces, edges) {
  neighbors <- vector("list", length(faces))
  for (adjacent in edges) for (face in adjacent) neighbors[[face]] <- union(
      neighbors[[face]],
      adjacent[adjacent != face]
  )
  unseen <- rep.int(TRUE, length(faces))
  components <- list()
  while (any(unseen)) {
    seed <- which(unseen)[[1L]]
    unseen[[seed]] <- FALSE
    queue <- seed
    index <- 1L
    while (index <= length(queue)) {
      face <- queue[[index]]
      index <- index + 1L
      for (neighbor in sort(neighbors[[face]])) {
        if (unseen[[neighbor]]) {
          unseen[[neighbor]] <- FALSE
          queue <- c(queue, neighbor)
        }
      }
    }
    components[[length(components) + 1L]] <- sort(queue)
  }
  components
}
vertex_fans <- function(vertex, faces, edges) {
  containing <- which(vapply(faces, function(face) vertex %in% face$vertices, FALSE))
  others <- rep.int(FALSE, length(faces))
  others[containing] <- TRUE
  neighbors <- vector("list", length(faces))
  for (key in names(edges)) {
    if (!(vertex %in% edge_vertices(key))) next
    participating <- edges[[key]]
    for (face in participating) neighbors[[face]] <- union(
        neighbors[[face]],
        participating[participating != face]
    )
  }
  fans <- list()
  while (any(others)) {
    seed <- which(others)[[1L]]
    others[[seed]] <- FALSE
    queue <- seed
    index <- 1L
    while (index <= length(queue)) {
      face <- queue[[index]]
      index <- index + 1L
      for (neighbor in sort(neighbors[[face]])) if (others[[neighbor]]) {
        others[[neighbor]] <- FALSE
        queue <- c(queue, neighbor)
      }
    }
    fans[[length(fans) + 1L]] <- sort(queue)
  }
  fans
}
analyze_mesh <- function(faces) {
  edges <- edge_table(faces)
  components <- list()
  face_components <- integer(length(faces))
  groups <- connected_components(faces, edges)
  for (number in seq_along(groups)) {
    ids <- groups[[number]]
    face_components[ids] <- number
    vertices <- sort(unique(unlist(lapply(faces[ids], function(face) face$vertices), use.names = FALSE)))
    component_edges <- names(edges)[vapply(edges, function(adjacent) any(adjacent %in% ids), FALSE)]
    components[[number]] <- record(number = number, faces = ids, vertices = vertices, edges = component_edges,
                                   boundary = component_edges[lengths(edges[component_edges]) == 1L], nonmanifold = component_edges[lengths(edges[component_edges]) >= 3L])
  }
  used <- sort(unique(unlist(lapply(faces, function(face) face$vertices), use.names = FALSE)))
  fans <- setNames(lapply(used, function(v) vertex_fans(v, faces, edges)), as.character(used))
  nonmanifold_vertices <- used[lengths(fans) >= 2L]
  for (component in components) {
    number <- component$number
    component$nonmanifold_vertices <- component$vertices[vapply(component$vertices, function(v) {
      sum(vapply(fans[[as.character(v)]], function(fan) any(face_components[fan] == number), FALSE)) >= 2L
    }, FALSE)]
  }
  list(
      edges = edges,
      edge_order = names(edges),
      components = components,
      face_components = face_components,
      fans = fans,
      nonmanifold_vertices = nonmanifold_vertices
  )
}
boundary_loops <- function(faces, mesh, contains_directed) {
  loops <- list()
  for (component in mesh$components) {
    unused <- component$boundary
    for (first in component$boundary) {
      if (!(first %in% unused)) next
      unused <- unused[unused != first]
      edge <- edge_vertices(first)
      a <- edge[[1L]]
      sequence <- edge
      current <- edge[[2L]]
      while (current != a) {
        choices <- unused[vapply(unused, function(key) current %in% edge_vertices(key), FALSE)]
        if (!length(choices)) break
        others <- vapply(choices, function(key) {
          pair <- edge_vertices(key)
          if (pair[[1L]] == current) pair[[2L]] else pair[[1L]]
        }, 0L)
        selected <- which.min(others)
        chosen <- choices[[selected]]
        current <- others[[selected]]
        unused <- unused[unused != chosen]
        sequence <- c(sequence, current)
      }
      closed <- tail(sequence, 1L) == a
      kind <- "open"
      count <- length(sequence) - 1L
      if (closed) {
        sequence <- head(sequence, -1L)
        count <- length(sequence)
        directed <- vapply(seq_len(count), function(i) {
          u <- sequence[[i]]
          v <- sequence[[i %% count + 1L]]
          face <- faces[[mesh$edges[[key_edge(u, v)]][[1L]]]]
          contains_directed(face$vertices, u, v)
        }, FALSE)
        if (all(directed)) kind <- "coherent" else if (!any(directed)) {
          kind <- "coherent"
          sequence <- c(sequence[[1L]], rev(sequence[-1L]))
        } else kind <- "mixed"
      }
      loops[[length(loops) + 1L]] <- record(
          number = length(loops) + 1L,
          component = component$number,
          vertices = sequence,
          length = count,
          kind = kind,
          filled = FALSE
      )
    }
  }
  loops
}
