cell_center <- function(cell) 100 * cell
cell_index <- function(grid, cell) cell[2] * grid$width + cell[1] + 1
inside <- function(grid, cell) cell[1] >= 0 && cell[1] < grid$width && cell[2] >= 0 && cell[2] < grid$height
terrain <- function(grid, cell) grid$rows[cell[2] + 1, cell[1] + 1]
is_rock <- function(grid, cell) terrain(grid, cell) == "#"
is_water <- function(grid, cell) terrain(grid, cell) == "~"
buildable <- function(grid, cell) terrain(grid, cell) == "."
read_map <- function() {
  lines <- readLines("input/map.txt", warn = FALSE)
  fields <- as.numeric(strsplit(lines[1], " ", fixed = TRUE)[[1]])
  width <- fields[1]
  height <- fields[2]
  rows <- do.call(rbind, strsplit(lines[seq_len(height) + 1], "", fixed = TRUE))
  found <- vector("list", 9)
  exit <- c(0, 0)
  for (y in seq_len(height) - 1) for (x in seq_len(width) - 1) {
    symbol <- rows[y + 1, x + 1]
    if (symbol %in% as.character(seq_len(9))) found[[as.integer(symbol)]] <- c(x, y) else if (symbol == "E") exit <- c(x, y)
  }
  list(width = width, height = height, rows = rows, exit = exit, spawns = Filter(Negate(is.null), found))
}
