squared_distance <- function(a, b) (a$x - b$x) * (a$x - b$x) + (a$y - b$y) * (a$y - b$y)
cell_key <- function(gx, gy) paste(gx, gy, sep = ":")
grid_index <- function(points, eps) {
    cells <- list()
    for (i in seq_along(points)) {
        point <- points[[i]]
        key <- cell_key(point$x %/% eps, point$y %/% eps)
        cells[[key]] <- c(cells[[key]], i)
    }
    list(points = points, eps = eps, cells = cells)
}
neighborhood <- function(grid, index) {
    point <- grid$points[[index]]
    column <- point$x %/% grid$eps
    row <- point$y %/% grid$eps
    neighbors <- integer()
    candidates <- 0L
    for (gy in seq.int(row - 1, row + 1)) for (gx in seq.int(column - 1, column + 1)) {
        for (other in grid$cells[[cell_key(gx, gy)]]) {
            candidates <- candidates + 1L
            if (squared_distance(
                point,
                grid$points[[other]]
            ) <= grid$eps * grid$eps) neighbors <- c(neighbors, other)
        }
    }
    list(neighbors = neighbors, candidates = candidates)
}
busiest_cell <- function(grid) {
    coordinates <- lapply(strsplit(names(grid$cells), ":", fixed = TRUE), as.numeric)
    sizes <- lengths(grid$cells)
    index <- order(
        -sizes,
        vapply(coordinates, function(cell) cell[2L], 0),
        vapply(coordinates, function(cell) cell[1L], 0)
    )[1L]
    c(coordinates[[index]], sizes[index])
}
brute_force_counts <- function(points, eps) vapply(
    points,
    function(point) sum(vapply(points, function(other) squared_distance(point, other) <= eps * eps, FALSE)),
    0L
)
