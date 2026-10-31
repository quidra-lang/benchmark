cross_product <- function(o, a, b) (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1])

chain <- function(points) {
  result <- list()
  for (point in points) {
    while (length(result) >= 2 && cross_product(result[[length(result) - 1]], tail(result, 1)[[1]], point) <= 0) {
      result <- head(result, -1)
    }
    result[[length(result) + 1]] <- point
  }
  result
}

points <- matrix(as.integer(c(
  3, 2, -6, 1, 8, 4, 0, 0, -3, 7, 4, -3, 1, -5, -2, 1, 5, 6, -6, -2, 2, -2, 7, -1, -3, 4, 2, 8, -6,
  3
)), ncol = 2, byrow = TRUE)
points <- points[order(points[, 1], points[, 2]), ]
point_list <- lapply(seq_len(nrow(points)), function(i) points[i, ])
lower <- chain(point_list)
upper <- chain(rev(point_list))
hull <- c(head(lower, -1), head(upper, -1))
cat(sprintf("hull: %d points\n", length(hull)))
twice_area <- 0L
for (i in seq_along(hull)) {
  point <- hull[[i]]
  next_point <- hull[[i %% length(hull) + 1]]
  cat(sprintf("(%d, %d)\n", point[1], point[2]))
  twice_area <- twice_area + point[1] * next_point[2] - next_point[1] * point[2]
}
cat(sprintf("area: %.1f\n", twice_area / 2))
