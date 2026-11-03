fill_polygons <- function(sequences, rule, clip, width) {
  edges <- list()
  for (vertices in sequences) if (nrow(vertices)) for (index in seq_len(nrow(vertices))) {
    next_index <- if (index < nrow(vertices)) index + 1L else 1L
    if (vertices[index, 2L] != vertices[next_index, 2L]) edges[[length(edges) + 1L]] <- rbind(vertices[index, ], vertices[next_index, ])
  }
  pixels <- integer()
  for (y in seq.int(clip[2L], clip[4L])) {
    crossings <- empty_points()
    for (edge in edges) {
      a <- edge[1L, ]
      b <- edge[2L, ]
      if (y < min(a[2L], b[2L]) || y >= max(a[2L], b[2L])) next
      denominator <- b[2L] - a[2L]
      numerator <- 2L * a[1L] * denominator + (2L * y + 1L - 2L * a[2L]) * (b[1L] - a[1L])
      direction <- if (denominator > 0L) 1L else -1L
      if (denominator < 0L) {
        denominator <- -denominator
        numerator <- -numerator
      }
      crossings <- rbind(crossings, c((numerator - denominator) %/% (2L * denominator) + 1L, direction))
    }
    if (!nrow(crossings)) next
    crossings <- crossings[order(crossings[, 1L], crossings[, 2L]), , drop = FALSE]
    count <- winding <- 0L
    index <- 1L
    for (x in seq.int(clip[1L], clip[3L])) {
      while (index <= nrow(crossings) && crossings[index, 1L] <= x) {
        count <- count + 1L
        winding <- winding + crossings[index, 2L]
        index <- index + 1L
      }
      if (if (rule == "evenodd") count %% 2L == 1L else winding != 0L) pixels <- c(pixels, y * width + x + 1L)
    }
  }
  pixels
}
fill_shape <- function(center, points, clip, width) {
  pixels <- integer()
  for (dy in unique(points[, 2L])) {
    y <- center[2L] + dy
    if (y < clip[2L] || y > clip[4L]) next
    extent <- max(abs(points[points[, 2L] == dy, 1L]))
    first <- max(clip[1L], center[1L] - extent)
    last <- min(clip[3L], center[1L] + extent)
    if (first <= last) pixels <- c(pixels, y * width + seq.int(first, last) + 1L)
  }
  pixels
}
flood_fill <- function(layer, seed, clip) {
  width <- layer$width
  number <- seed[2L] * width + seed[1L] + 1L
  painted <- layer$painted[number]
  color <- layer$colors[number, ]
  seen <- rep(FALSE, length(layer$painted))
  seen[number] <- TRUE
  queue <- integer(length(seen))
  queue[1L] <- number
  head <- tail <- 1L
  while (head <= tail) {
    id <- queue[head]
    head <- head + 1L
    point <- c((id - 1L) %% width, (id - 1L) %/% width)
    for (delta in list(c(1L, 0L), c(-1L, 0L), c(0L, 1L), c(0L, -1L))) {
      other <- point + delta
      if (!contains(clip, other)) next
      next_id <- other[2L] * width + other[1L] + 1L
      if (seen[next_id] || layer$painted[next_id] != painted || (painted && any(layer$colors[next_id, ] != color))) next
      seen[next_id] <- TRUE
      tail <- tail + 1L
      queue[tail] <- next_id
    }
  }
  which(seen)
}
