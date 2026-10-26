text <- c(
  "#############",
  "#S..#.......#",
  "#.#.#.###.#.#",
  "#.#...#...#.#",
  "#.###.#.###.#",
  "#...#...#...#",
  "###.#####.#.#",
  "#.......#..G#",
  "#############"
)
maze <- do.call(rbind, strsplit(text, "", fixed = TRUE))
start <- which(maze == "S", arr.ind = TRUE)[1, ]
goal <- which(maze == "G", arr.ind = TRUE)[1, ]
parent_row <- parent_column <- matrix(0L, 9, 13)
seen <- matrix(FALSE, 9, 13)
seen[start[1], start[2]] <- TRUE
queue <- list(start)
head_index <- 1
while (head_index <= length(queue)) {
  cell <- queue[[head_index]]
  head_index <- head_index + 1
  if (all(cell == goal)) break
  for (direction in list(c(-1, 0), c(1, 0), c(0, -1), c(0, 1))) {
    next_cell <- cell + direction
    r <- next_cell[1]
    c_value <- next_cell[2]
    if (r >= 1 && r <= 9 && c_value >= 1 && c_value <= 13 && maze[r, c_value] != "#" && !seen[r, c_value]) {
      seen[r, c_value] <- TRUE
      parent_row[r, c_value] <- cell[1]
      parent_column[r, c_value] <- cell[2]
      queue[[length(queue) + 1]] <- next_cell
    }
  }
}
cell <- goal
steps <- 0
while (!all(cell == start)) {
  r <- cell[1]
  c_value <- cell[2]
  if (maze[r, c_value] == ".") maze[r, c_value] <- "*"
  cell <- c(parent_row[r, c_value], parent_column[r, c_value])
  steps <- steps + 1
}
cat(sprintf("steps: %d\n", steps))
for (r in 1:9) cat(paste(maze[r, ], collapse = ""), "\n", sep = "")
