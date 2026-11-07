kd_node <- function(point,axis,left=NULL,right=NULL) {
  node <- new.env(parent=emptyenv())
  node$point <- point
  node$axis <- axis
  node$left <- left
  node$right <- right
  node
}
kd_key <- function(point,axis) if (axis == 0L) point[c(2L,3L,1L)] else point[c(3L,2L,1L)]
key_less <- function(a,b) {
  different <- which(a != b)
  length(different) > 0L && a[different[1L]] < b[different[1L]]
}
kd_build <- function(points,depth=0L) {
  if (!length(points)) return(NULL)
  axis <- depth %% 2L
  keys <- do.call(rbind,lapply(points,function(point) kd_key(point,axis)))
  ordered <- points[order(keys[,1L],keys[,2L],keys[,3L])]
  middle <- length(points) %/% 2L+1L
  kd_node(
      ordered[[middle]],
      axis,
      kd_build(head(ordered,middle-1L),depth+1L),
      kd_build(tail(ordered,length(ordered)-middle),depth+1L)
  )
}
kd_insert <- function(root,point) {
  if (is.null(root)) return(kd_node(point,0L))
  node <- root
  repeat {
    side <- if (key_less(kd_key(point,node$axis),kd_key(node$point,node$axis))) "left" else "right"
    child <- node[[side]]
    if (is.null(child)) {
      node[[side]] <- kd_node(point,1L-node$axis)
      return(root)
    }
    node <- child
  }
}
kd_minimum <- function(root,axis) {
  best <- root$point
  pending <- list(root)
  while (length(pending)) {
    node <- pending[[length(pending)]]
    pending <- head(pending,-1L)
    if (node$axis == axis && !is.null(node$left)) {
      pending[[length(pending)+1L]] <- node$left
      next
    }
    if (key_less(kd_key(node$point,axis),kd_key(best,axis))) best <- node$point
    if (node$axis != axis) {
      if (!is.null(node$left)) pending[[length(pending)+1L]] <- node$left
      if (!is.null(node$right)) pending[[length(pending)+1L]] <- node$right
    }
  }
  best
}
kd_delete <- function(root,point) {
  parent <- NULL
  node <- root
  side <- "left"
  while (!is.null(node)) {
    if (node$point[1L] != point[1L]) {
      parent <- node
      side <- if (key_less(kd_key(point,node$axis),kd_key(node$point,node$axis))) "left" else "right"
      node <- node[[side]]
    } else if (!is.null(node$right)) {
      point <- kd_minimum(node$right,node$axis)
      node$point <- point
      parent <- node
      side <- "right"
      node <- node$right
    } else if (!is.null(node$left)) {
      point <- kd_minimum(node$left,node$axis)
      node$point <- point
      node$right <- node$left
      node$left <- NULL
      parent <- node
      side <- "right"
      node <- node$right
    } else {
      if (is.null(parent)) return(NULL)
      parent[[side]] <- NULL
      return(root)
    }
  }
  root
}
