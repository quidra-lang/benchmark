region_code <- function(point, clip) sum(c(1L, 2L, 4L, 8L) * c(point[1L] < clip[1L], point[1L] > clip[3L], point[2L] < clip[2L], point[2L] > clip[4L]))
clip_segment <- function(start, end, clip) {
  repeat {
    first <- region_code(start, clip)
    last <- region_code(end, clip)
    if (first == 0L && last == 0L) return(rbind(start, end))
    if (bitwAnd(first, last) != 0L) return(NULL)
    outside <- if (first) start else end
    other <- if (first) end else start
    code <- if (first) first else last
    ax <- outside[1L]
    ay <- outside[2L]
    bx <- other[1L]
    by <- other[2L]
    if (bitwAnd(code, 4L)) point <- c(ax + round_ratio((bx - ax) * (clip[2L] - ay), by - ay), clip[2L])
    else if (bitwAnd(code, 8L)) point <- c(ax + round_ratio((bx - ax) * (clip[4L] - ay), by - ay), clip[4L])
    else if (bitwAnd(code, 2L)) point <- c(clip[3L], ay + round_ratio((by - ay) * (clip[3L] - ax), bx - ax))
    else point <- c(clip[1L], ay + round_ratio((by - ay) * (clip[1L] - ax), bx - ax))
    if (first) start <- point else end <- point
  }
}
clip_polygon <- function(vertices, clip) {
  boundaries <- list(c(1L, clip[1L], 1L), c(1L, clip[3L] + 1L, 0L), c(2L, clip[2L], 1L), c(2L, clip[4L] + 1L, 0L))
  for (boundary in boundaries) {
    output <- empty_points()
    if (!nrow(vertices)) return(output)
    axis <- boundary[1L]
    limit <- boundary[2L]
    inside <- function(point) if (boundary[3L]) point[axis] >= limit else point[axis] <= limit
    intersection <- function(start, end) {
      if (axis == 1L) c(limit, start[2L] + round_ratio((limit - start[1L]) * (end[2L] - start[2L]), end[1L] - start[1L]))
      else c(start[1L] + round_ratio((limit - start[2L]) * (end[1L] - start[1L]), end[2L] - start[2L]), limit)
    }
    for (index in seq_len(nrow(vertices))) {
      start <- vertices[if (index == 1L) nrow(vertices) else index - 1L, ]
      end <- vertices[index, ]
      if (inside(end)) {
        if (!inside(start)) output <- rbind(output, intersection(start, end))
        output <- rbind(output, end)
      } else if (inside(start)) output <- rbind(output, intersection(start, end))
    }
    vertices <- output
  }
  vertices
}
