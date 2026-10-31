direction_names <- c("N", "NE", "E", "SE", "S", "SW", "W", "NW")
directions <- matrix(c(0, -1, 1, -1, 1, 0, 1, 1, 0, 1, -1, 1, -1, 0, -1, -1), ncol = 2L, byrow = TRUE)
passable <- function(level, x, y) level$terrain[y + 1L, x + 1L] %in% c(".", "#", "+", "<", ">")
can_move <- function(level, x, y, dx, dy) {
  passable(level, x + dx, y + dy) && (dx == 0 || dy == 0 || (level$terrain[y + 1L, x + 1L] != "+" && level$terrain[y + dy + 1L, x + dx + 1L] != "+"))
}

line_cells <- function(x0, y0, x1, y1) {
  dx <- abs(x1 - x0)
  dy <- abs(y1 - y0)
  sx <- if (x1 > x0) 1 else -1
  sy <- if (y1 > y0) 1 else -1
  error <- dx - dy
  x <- x0
  y <- y0
  cells <- matrix(numeric(), 0L, 2L)
  while (x != x1 || y != y1) {
    e2 <- 2 * error
    if (e2 > -dy) {
      error <- error - dy
      x <- x + sx
    }
    if (e2 < dx) {
      error <- error + dx
      y <- y + sy
    }
    cells <- rbind(cells, c(x, y))
  }
  cells
}

field_of_view <- function(level, px, py, radius) {
  visible <- matrix(FALSE, level$height, level$width)
  for (y in seq.int(max(0, py - radius), min(level$height - 1L, py + radius))) {
    for (x in seq.int(max(0, px - radius), min(level$width - 1L, px + radius))) {
      if ((x - px)^2 + (y - py)^2 > radius^2) next
      cells <- line_cells(px, py, x, y)
      clear <- TRUE
      for (i in seq_len(max(0L, nrow(cells) - 1L))) {
        if (!passable(level, cells[i, 1L], cells[i, 2L])) {
          clear <- FALSE
          break
        }
      }
      visible[y + 1L, x + 1L] <- clear
    }
  }
  visible
}

distances <- function(level, px, py) {
  distance <- matrix(-1L, level$height, level$width)
  distance[py + 1L, px + 1L] <- 0L
  queue <- list(c(px, py))
  head <- 1L
  while (head <= length(queue)) {
    point <- queue[[head]]
    head <- head + 1L
    for (i in seq_len(nrow(directions))) {
      dx <- directions[i, 1L]
      dy <- directions[i, 2L]
      nx <- point[1L] + dx
      ny <- point[2L] + dy
      if (can_move(level, point[1L], point[2L], dx, dy) && distance[ny + 1L, nx + 1L] < 0L) {
        distance[ny + 1L, nx + 1L] <- distance[point[2L] + 1L, point[1L] + 1L] + 1L
        queue[[length(queue) + 1L]] <- c(nx, ny)
      }
    }
  }
  distance
}
