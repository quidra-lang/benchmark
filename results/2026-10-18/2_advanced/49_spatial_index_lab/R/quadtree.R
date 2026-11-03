CHILD_NAMES <- c("NW","NE","SW","SE")
quad_node <- function(x,y,size) {
  node <- new.env(parent=emptyenv())
  node$x <- x
  node$y <- y
  node$size <- size
  node$points <- list()
  node$children <- list()
  node
}
quad_destination <- function(
    node,
    p
) 1L+as.integer(p[2L] >= node$x+node$size %/% 2L)+2L*as.integer(p[3L] >= node$y+node$size %/% 2L)
quad_insert <- function(root,point,capacity) {
  node <- root
  while (length(node$children)) node <- node$children[[quad_destination(node,point)]]
  points <- c(node$points,list(point))
  node$points <- points[order(vapply(points,`[`,integer(1),1L))]
  if (length(node$points) > capacity) {
    half <- node$size %/% 2L
    node$children <- list(quad_node(node$x,node$y,half),quad_node(node$x+half,node$y,half),
      quad_node(node$x,node$y+half,half),quad_node(node$x+half,node$y+half,half))
    previous <- node$points
    node$points <- list()
    for (point in previous) quad_insert(node,point,capacity)
  }
}
quad_delete <- function(root,point,capacity) {
  ancestors <- list()
  node <- root
  while (length(node$children)) {
    ancestors[[length(ancestors)+1L]] <- node
    node <- node$children[[quad_destination(node,point)]]
  }
  node$points <- Filter(function(p) p[1L] != point[1L],node$points)
  for (node in rev(ancestors)) {
    if (any(vapply(node$children,function(child) length(child$children) > 0L,logical(1)))) break
    points <- unlist(lapply(node$children,function(child) child$points),recursive=FALSE)
    if (length(points) > capacity) break
    node$points <- points[order(vapply(points,`[`,integer(1),1L))]
    node$children <- list()
  }
}
quad_build <- function(points,world,capacity) {
  root <- quad_node(0L,0L,world)
  for (point in points) quad_insert(root,point,capacity)
  root
}
