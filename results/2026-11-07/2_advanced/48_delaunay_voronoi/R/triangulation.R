canonical <- function(a,b,c) {
  vertices <- c(a,b,c)
  start <- which.min(vertices)
  vertices[((seq_len(3L)+start-2L) %% 3L)+1L]
}
make_triangulation <- function(points) {
  mesh <- new.env(parent=emptyenv())
  mesh$points <- points
  mesh$directed <- matrix(0L,length(points),length(points))
  mesh$initial <- if (orient(points[[1L]],points[[2L]],points[[3L]]) > 0) c(1L,2L,3L) else c(1L,3L,2L)
  add_triangle(mesh,mesh$initial[1L],mesh$initial[2L],mesh$initial[3L])
  mesh
}
add_triangle <- function(mesh,a,b,c) {
  mesh$directed[a,b] <- c
  mesh$directed[b,c] <- a
  mesh$directed[c,a] <- b
}
remove_triangle <- function(mesh,a,b,c) {
  mesh$directed[a,b] <- 0L
  mesh$directed[b,c] <- 0L
  mesh$directed[c,a] <- 0L
}
triangles <- function(mesh) {
  edges <- which(mesh$directed != 0L,arr.ind=TRUE)
  rows <- lapply(
      seq_len(nrow(edges)),
      function(i) canonical(edges[i,1L],edges[i,2L],mesh$directed[edges[i,1L],edges[i,2L]])
  )
  rows <- unique(do.call(rbind,rows))
  rows <- rows[order(rows[,1L],rows[,2L],rows[,3L]),,drop=FALSE]
  lapply(seq_len(nrow(rows)),function(i) rows[i,])
}
hull_edges <- function(mesh) {
  edges <- which(mesh$directed != 0L & t(mesh$directed) == 0L,arr.ind=TRUE)
  edges <- edges[order(edges[,1L],edges[,2L]),,drop=FALSE]
  lapply(seq_len(nrow(edges)),function(i) edges[i,])
}
insert_site <- function(mesh,s) {
  points <- mesh$points
  containing <- NULL
  for (triangle in triangles(mesh)) {
    a <- triangle[1L]
    b <- triangle[2L]
    c <- triangle[3L]
    if (orient(points[[a]],points[[b]],points[[s]]) > 0 && orient(points[[b]],points[[c]],points[[s]]) > 0 &&
        orient(points[[c]],points[[a]],points[[s]]) > 0) {
      containing <- triangle
      break
    }
  }
  if (is.null(containing)) {
    visible_edges <- Filter(
        function(edge) orient(points[[edge[1L]]],points[[edge[2L]]],points[[s]]) < 0,
        hull_edges(mesh)
    )
    check <- lapply(visible_edges,rev)
    kind <- "outside"
    visible <- length(check)
  } else {
    a <- containing[1L]
    b <- containing[2L]
    c <- containing[3L]
    remove_triangle(mesh,a,b,c)
    check <- list(c(a,b),c(b,c),c(c,a))
    kind <- "inside"
    visible <- 0L
  }
  for (edge in check) add_triangle(mesh,edge[1L],edge[2L],s)
  flips <- 0L
  while (length(check)) {
    edge <- check[[length(check)]]
    check <- head(check,-1L)
    a <- edge[1L]
    b <- edge[2L]
    q <- mesh$directed[b,a]
    if (q != 0L && incircle(points[[a]],points[[b]],points[[s]],points[[q]]) > 0) {
      remove_triangle(mesh,a,b,s)
      remove_triangle(mesh,b,a,q)
      add_triangle(mesh,a,q,s)
      add_triangle(mesh,q,b,s)
      check <- unique(c(check,list(c(a,q),c(q,b))))
      flips <- flips+1L
    }
  }
  list(
      site=s,
      kind=kind,
      containing=containing,
      visible=visible,
      flips=flips,
      triangles=sum(mesh$directed != 0L)/3L,
      hull=length(hull_edges(mesh))
  )
}
visibility_walk <- function(points,query,triangles,edge_triangles) {
  path <- 1L
  repeat {
    triangle <- triangles[[tail(path,1L)]]
    edges <- list(triangle[c(1L,2L)],triangle[c(2L,3L)],triangle[c(3L,1L)])
    crossing <- Filter(function(edge) orient(points[[edge[1L]]],points[[edge[2L]]],query) < 0,edges)
    if (!length(crossing)) return(list(path=path,outside=NULL))
    edge <- crossing[[1L]]
    following <- edge_triangles[edge[2L],edge[1L]]
    if (following == 0L) return(list(path=path,outside=sort(edge)))
    path <- c(path,following)
  }
}
