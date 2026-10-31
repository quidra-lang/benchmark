split_polygons <- function(polygons) {
  triangles <- list()
  for (polygon in polygons) {
    corners <- polygon$vertices
    for (i in seq.int(2L, length(corners) - 1L)) triangles[[length(triangles) + 1L]] <- new_face(
        length(triangles) + 1L,
        polygon$number,
        polygon$line,
        polygon$group,
        corners[c(1L, i, i + 1L)]
    )
  }
  triangles
}
snapped_vertices <- function(vertices, spacing) {
  points <- vertices
  changed <- list()
  for (i in seq_len(nrow(vertices))) {
    rounded <- spacing * ((2 * vertices[i, ] + spacing) %/% (2 * spacing))
    points[i, ] <- rounded
    if (any(rounded != vertices[i, ])) changed[[length(changed) + 1L]] <- list(
        number = i,
        before = vertices[i, ],
        after = rounded
    )
  }
  list(points = points, changed = changed)
}
representatives <- function(points, merge) {
  owner <- new.env(hash = TRUE, parent = emptyenv())
  result <- integer(nrow(points))
  for (i in seq_len(nrow(points))) {
    if (!merge) result[[i]] <- i else {
      key <- paste(sprintf("%.0f", points[i, ]), collapse = ":")
      if (!exists(key, envir = owner, inherits = FALSE)) owner[[key]] <- i
      result[[i]] <- owner[[key]]
    }
  }
  result
}
cleaned_faces <- function(triangles, points, representative, remove_zero, remove_duplicate) {
  faces <- removed <- list()
  seen <- character()
  for (triangle in triangles) {
    corners <- representative[triangle$vertices]
    reason <- NULL
    if (length(unique(corners)) < 3L) reason <- "repeated" else if (remove_zero) {
      p <- points[corners[[1L]], ]
      q <- points[corners[[2L]], ]
      r <- points[corners[[3L]], ]
      if (all(cross(q - p, r - p) == 0)) reason <- "zero_area"
    }
    if (is.null(reason)) {
      identifier <- paste(sort(corners), collapse = ":")
      if (remove_duplicate && identifier %in% seen) reason <- "duplicate" else seen <- union(seen, identifier)
    }
    if (is.null(reason)) faces[[length(faces) + 1L]] <- new_face(
        triangle$triangle,
        triangle$polygon,
        triangle$line,
        triangle$group,
        corners
    ) else removed[[length(removed) + 1L]] <- list(face = triangle, reason = reason)
  }
  list(faces = faces, removed = removed)
}
remap_vertices <- function(original, snapped, representative, faces, keep_unused) {
  present <- if (keep_unused) which(representative == seq_len(nrow(original))) else sort(unique(unlist(
      lapply(faces, function(face) face$vertices),
      use.names = FALSE
  )))
  numbers <- setNames(seq_along(present), as.character(present))
  mapped <- lapply(
      faces,
      function(face) new_face(
          face$triangle,
          face$polygon,
          face$line,
          face$group,
          unname(numbers[as.character(face$vertices)])
      )
  )
  list(points = snapped[present, , drop = FALSE], faces = mapped, numbers = numbers)
}
fill_loops <- function(faces, loops, max_length, permitted) {
  added <- list()
  for (loop in loops) {
    loop$filled <- FALSE
    corners <- loop$vertices
    count <- loop$length
    if (loop$kind != "coherent" || count < 3L || count > max_length || length(unique(corners)) != count || !(loop$component %in% permitted)) next
    for (i in seq.int(3L, count)) added[[length(added) + 1L]] <- new_face(
        0L,
        0L,
        0L,
        "fill",
        corners[c(1L, i, i - 1L)]
    )
    loop$filled <- TRUE
  }
  list(faces = c(faces, added), added = added)
}
