has_directed <- function(triangle, start, stop) any(vapply(
    triangle_edges(triangle),
    function(edge) edge[[1L]] == start && edge[[2L]] == stop,
    FALSE
))
flip <- function(face) face$vertices <- face$vertices[c(1L, 3L, 2L)]
inconsistent_edges <- function(faces, edges) {
  names(edges)[vapply(names(edges), function(key) {
    adjacent <- edges[[key]]
    if (length(adjacent) != 2L) return(FALSE)
    edge <- edge_vertices(key)
    has_directed(faces[[adjacent[[1L]]]]$vertices, edge[[1L]], edge[[2L]]) == has_directed(
        faces[[adjacent[[2L]]]]$vertices,
        edge[[1L]],
        edge[[2L]]
    )
  }, FALSE)]
}
repair_orientation <- function(faces, edges) {
  visited <- logical(length(faces))
  for (seed in seq_along(faces)) {
    if (visited[[seed]]) next
    visited[[seed]] <- TRUE
    queue <- seed
    index <- 1L
    while (index <= length(queue)) {
      current <- queue[[index]]
      index <- index + 1L
      for (edge in triangle_edges(faces[[current]]$vertices)) {
        adjacent <- edges[[key_edge(edge[[1L]], edge[[2L]])]]
        if (length(adjacent) != 2L) next
        other <- if (adjacent[[1L]] == current) adjacent[[2L]] else adjacent[[1L]]
        if (visited[[other]]) next
        if (has_directed(faces[[other]]$vertices, edge[[1L]], edge[[2L]])) flip(faces[[other]])
        visited[[other]] <- TRUE
        queue <- c(queue, other)
      }
    }
  }
}
orientable_components <- function(faces, mesh) {
  copied <- lapply(faces, copy_face)
  repair_orientation(copied, mesh$edges)
  violations <- inconsistent_edges(copied, mesh$edges)
  vapply(mesh$components, function(component) !any(component$edges %in% violations), FALSE)
}
