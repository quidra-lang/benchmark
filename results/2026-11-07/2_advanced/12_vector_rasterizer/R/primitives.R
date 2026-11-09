empty_points <- function() matrix(integer(), 0L, 2L)
bresenham <- function(start, end) {
  x <- start[1L]
  y <- start[2L]
  dx <- abs(end[1L] - x)
  dy <- -abs(end[2L] - y)
  sx <- if (x < end[1L]) 1L else -1L
  sy <- if (y < end[2L]) 1L else -1L
  error <- dx + dy
  points <- empty_points()
  repeat {
    points <- rbind(points, c(x, y))
    if (x == end[1L] && y == end[2L]) return(points)
    twice <- 2L * error
    if (twice >= dy) {
      error <- error + dy
      x <- x + sx
    }
    if (twice <= dx) {
      error <- error + dx
      y <- y + sy
    }
  }
}
expand_square <- function(point, width) {
  low <- -((width - 1L) %/% 2L)
  offsets <- seq.int(low, low + width - 1L)
  cbind(rep(offsets + point[1L], times = width), rep(offsets + point[2L], each = width))
}
circle_points <- function(radius) {
  points <- empty_points()
  a <- radius
  b <- 0L
  error <- 1L - radius
  while (a >= b) {
    points <- rbind(points, c(a, b), c(b, a), c(-b, a), c(-a, b), c(-a, -b), c(-b, -a), c(b, -a), c(a, -b))
    b <- b + 1L
    if (error < 0L) error <- error + 2L * b + 1L else {
      a <- a - 1L
      error <- error + 2L * (b - a) + 1L
    }
  }
  unique(points)
}
ellipse_points <- function(rx, ry) {
  rx2 <- rx * rx
  ry2 <- ry * ry
  x <- 0L
  y <- ry
  points <- rbind(c(0L, ry), c(0L, -ry))
  while (ry2 * x < rx2 * y) {
    decision <- 4L * ry2 * (x + 1L) * (x + 1L) + rx2 * (2L * y - 1L) * (2L * y - 1L) - 4L * rx2 * ry2
    x <- x + 1L
    if (decision >= 0L) y <- y - 1L
    points <- rbind(points, c(x, y), c(-x, y), c(x, -y), c(-x, -y))
  }
  while (y > 0L) {
    decision <- ry2 * (2L * x + 1L) * (2L * x + 1L) + 4L * rx2 * (y - 1L) * (y - 1L) - 4L * rx2 * ry2
    y <- y - 1L
    if (decision <= 0L) x <- x + 1L
    points <- rbind(points, c(x, y), c(-x, y), c(x, -y), c(-x, -y))
  }
  unique(points)
}
bezier_points <- function(controls, segments) {
  degree <- nrow(controls) - 1L
  scale <- if (degree == 2L) segments * segments else segments * segments * segments
  points <- empty_points()
  for (index in 0:segments) {
    rest <- segments - index
    weights <- if (degree == 2L) c(rest * rest, 2L * index * rest, index * index) else c(rest * rest * rest, 3L * index * rest * rest, 3L * index * index * rest, index * index * index)
    points <- rbind(points, c(round_ratio(sum(weights * controls[, 1L]), scale), round_ratio(sum(weights * controls[, 2L]), scale)))
  }
  points
}
