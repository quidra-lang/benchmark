grid <- c(".......","..#....","....#..",".#.....","...#.#.",".......")
count_paths <- function(obstacles) {
    paths <- matrix(0L,nrow=length(grid),ncol=nchar(grid[1]))
    for (row in seq_len(nrow(paths))) for (column in seq_len(ncol(paths))) {
        if (obstacles && substr(grid[row],column,column) == "#") next
        if (row == 1 && column == 1) {
            paths[row,column] <- 1L
        } else {
            paths[row,column] <- (if (row > 1) paths[row-1,column] else 0L) + (if (column > 1) paths[row,column-1] else 0L)
        }
    }
    paths[nrow(paths),ncol(paths)]
}
cat(sprintf("without obstacles: %d\nwith obstacles: %d\n",count_paths(FALSE),count_paths(TRUE)))
