directions <- list(c(0, -1), c(1, 0), c(0, 1), c(-1, 0))
neighbor <- function(cell, direction) cell + directions[[direction]]
field_at <- function(field, cell) field$dist[cell_index(field$grid, cell)]
new_distance_field <- function(grid, towers) {
  dist <- rep(-1, grid$width * grid$height)
  dist[cell_index(grid, grid$exit)] <- 0
  queue <- list(grid$exit)
  head <- 1
  while (head <= length(queue)) {
    cell <- queue[[head]]
    head <- head + 1
    for (direction in seq_len(4)) {
      following <- neighbor(cell, direction)
      if (inside(grid, following) && !is_rock(grid, following) && !towers[cell_index(grid, following)] && dist[cell_index(grid, following)] < 0) {
        dist[cell_index(grid, following)] <- dist[cell_index(grid, cell)] + 1
        queue[[length(queue) + 1]] <- following
      }
    }
  }
  list(grid = grid, exit = grid$exit, dist = dist)
}
field_direction <- function(field, cell) {
  best <- 0L
  best_dist <- 0
  for (direction in seq_len(4)) {
    following <- neighbor(cell, direction)
    if (!inside(field$grid, following)) next
    distance <- field_at(field, following)
    if (distance >= 0 && (!best || distance < best_dist)) {
      best <- direction
      best_dist <- distance
    }
  }
  best
}
next_cell <- function(field, cell) neighbor(cell, field_direction(field, cell))
spawn_path <- function(field, start) {
  cells <- list(start)
  while (!all(tail(cells, 1)[[1]] == field$exit)) cells[[length(cells) + 1]] <- next_cell(field, tail(cells, 1)[[1]])
  cells
}
