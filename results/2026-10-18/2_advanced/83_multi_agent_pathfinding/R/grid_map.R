GRID_ACTIONS <- list(c(0L, 0L), c(0L, -1L), c(1L, 0L), c(0L, 1L), c(-1L, 0L))
GRID_ACTION_NAMES <- c(".", "N", "E", "S", "W")
read_grid <- function() {
    lines <- readLines("input/map.txt", warn = FALSE)
    dimensions <- as.integer(strsplit(lines[1L], " ", fixed = TRUE)[[1L]])
    rows <- lines[-1L]
    free <- unlist(
        lapply(rows, function(row) strsplit(row, "", fixed = TRUE)[[1L]] == "."),
        use.names = FALSE
    )
    list(width = dimensions[1L], height = dimensions[2L], rows = rows, free = free)
}
read_agents <- function(grid) {
    lapply(readLines("input/agents.csv", warn = FALSE)[-1L], function(line) {
        fields <- as.integer(strsplit(line, ",", fixed = TRUE)[[1L]])
        list(
            id = fields[1L],
            start = fields[3L] * grid$width + fields[2L],
            goal = fields[5L] * grid$width + fields[4L],
            name = intToUtf8(65L + fields[1L])
        )
    })
}
destinations <- function(grid, cell) {
    x <- cell %% grid$width
    y <- cell %/% grid$width
    result <- list()
    for (index in seq_along(GRID_ACTIONS)) {
        nx <- x + GRID_ACTIONS[[index]][1L]
        ny <- y + GRID_ACTIONS[[index]][2L]
        if (nx >= 0L && nx < grid$width && ny >= 0L && ny < grid$height) {
            destination <- ny * grid$width + nx
            if (grid$free[destination + 1L]) result[[length(result) + 1L]] <- list(
                cell = destination,
                action = GRID_ACTION_NAMES[index]
            )
        }
    }
    result
}
grid_neighbors <- function(grid, cell) vapply(
    Filter(function(entry) entry$action != ".", destinations(grid, cell)),
    function(entry) entry$cell,
    0L
)
distance_table <- function(grid, goal) {
    distances <- rep(-1L, length(grid$free))
    distances[goal + 1L] <- 0L
    queue <- goal
    index <- 1L
    while (index <= length(queue)) {
        cell <- queue[index]
        index <- index + 1L
        for (next_cell in grid_neighbors(grid, cell)) {
            if (distances[next_cell + 1L] == -1L) {
                distances[next_cell + 1L] <- distances[cell + 1L] + 1L
                queue <- c(queue, next_cell)
            }
        }
    }
    distances
}
