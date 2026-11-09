make_grid <- function(world,cell_size,points) {
  grid <- new.env(parent=emptyenv())
  grid$world <- world
  grid$cell_size <- cell_size
  grid$side <- world %/% cell_size
  grid$cells <- list()
  for (r in seq_len(grid$side)-1L) for (column in seq_len(grid$side)-1L) {
    cell <- new.env(parent=emptyenv())
    cell$column <- column
    cell$row <- r
    x <- column*cell_size
    y <- r*cell_size
    cell$box <- c(x,y,x+cell_size-1L,y+cell_size-1L)
    cell$points <- list()
    grid$cells[[length(grid$cells)+1L]] <- cell
  }
  for (point in points) grid_insert(grid,point)
  grid
}
grid_position <- function(grid,point) point[2:3] %/% grid$cell_size
grid_cell <- function(grid,point) {
  position <- grid_position(grid,point)
  grid$cells[[position[2L]*grid$side+position[1L]+1L]]
}
grid_insert <- function(grid,point) {
  cell <- grid_cell(grid,point)
  points <- c(cell$points,list(point))
  cell$points <- points[order(vapply(points,`[`,integer(1),1L))]
}
grid_delete <- function(grid,point) {
  cell <- grid_cell(grid,point)
  cell$points <- Filter(function(p) p[1L] != point[1L],cell$points)
}
