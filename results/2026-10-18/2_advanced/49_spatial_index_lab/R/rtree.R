point_box <- function(p) p[c(2L,3L,2L,3L)]
area <- function(b) (b[3L]-b[1L])*(b[4L]-b[2L])
mbr <- function(a,b) c(min(a[1L],b[1L]),min(a[2L],b[2L]),max(a[3L],b[3L]),max(a[4L],b[4L]))
enlargement <- function(a,b) area(mbr(a,b))-area(a)
contains <- function(a,b) a[1L] <= b[1L] && b[3L] <= a[3L] && a[2L] <= b[2L] && b[4L] <= a[4L]
intersects <- function(a,b) a[1L] <= b[3L] && b[1L] <= a[3L] && a[2L] <= b[4L] && b[2L] <= a[4L]
overlap <- function(a,b) {
  w <- min(a[3L],b[3L])-max(a[1L],b[1L])
  h <- min(a[4L],b[4L])-max(a[2L],b[2L])
  if (w > 0L && h > 0L) w*h else 0L
}
rentry <- function(box,id=0L,child=NULL) {
  entry <- new.env(parent=emptyenv())
  entry$box <- box
  entry$id <- id
  entry$child <- child
  entry
}
rnode <- function(level,entries=list(),parent=NULL) {
  node <- new.env(parent=emptyenv())
  node$level <- level
  node$entries <- entries
  node$parent <- parent
  adopt_children(node)
  node
}
adopt_children <- function(node) {
  if (node$level > 0L) for (entry in node$entries) entry$child$parent <- node
}
node_box <- function(node) Reduce(mbr,lapply(node$entries,function(entry) entry$box))
quadratic_split <- function(tree,node) {
  entries <- node$entries
  best <- -.Machine$integer.max
  seeds <- c(1L,2L)
  for (i in seq_len(length(entries)-1L)) for (j in seq.int(i+1L,length(entries))) {
    a <- entries[[i]]$box
    b <- entries[[j]]$box
    waste <- area(mbr(a,b))-area(a)-area(b)
    if (waste > best) {
      best <- waste
      seeds <- c(i,j)
    }
  }
  group1 <- entries[seeds[1L]]
  group2 <- entries[seeds[2L]]
  box1 <- group1[[1L]]$box
  box2 <- group2[[1L]]$box
  rest <- entries[-seeds]
  while (length(rest)) {
    if (length(group1)+length(rest) == tree$minimum) {
      group1 <- c(group1,rest)
      break
    }
    if (length(group2)+length(rest) == tree$minimum) {
      group2 <- c(group2,rest)
      break
    }
    first <- vapply(rest,function(entry) enlargement(box1,entry$box),integer(1))
    second <- vapply(rest,function(entry) enlargement(box2,entry$box),integer(1))
    selected <- which.max(abs(first-second))
    entry <- rest[[selected]]
    rest <- rest[-selected]
    key1 <- c(first[selected],area(box1),length(group1),1L)
    key2 <- c(second[selected],area(box2),length(group2),2L)
    if (key_less(key1,key2)) {
      group1 <- c(group1,list(entry))
      box1 <- mbr(box1,entry$box)
    } else {
      group2 <- c(group2,list(entry))
      box2 <- mbr(box2,entry$box)
    }
  }
  node$entries <- group1
  adopt_children(node)
  rnode(node$level,group2,node$parent)
}
rtree_insert <- function(tree,entry,level=0L) {
  node <- tree$root
  while (node$level > level) {
    gains <- vapply(node$entries,function(candidate) enlargement(candidate$box,entry$box),integer(1))
    areas <- vapply(node$entries,function(candidate) area(candidate$box),integer(1))
    selected <- order(gains,areas,seq_along(gains))[1L]
    node <- node$entries[[selected]]$child
  }
  node$entries <- c(node$entries,list(entry))
  if (level > 0L) entry$child$parent <- node
  repeat {
    sibling <- if (length(node$entries) > tree$maximum) quadratic_split(tree,node) else NULL
    parent <- node$parent
    if (is.null(parent)) {
      if (!is.null(sibling)) tree$root <- rnode(
          node$level+1L,
          list(rentry(node_box(node),child=node),rentry(node_box(sibling),child=sibling))
      )
      return(invisible(NULL))
    }
    index <- which(vapply(parent$entries,function(e) identical(e$child,node),logical(1)))[1L]
    parent$entries[[index]]$box <- node_box(node)
    if (!is.null(sibling)) {
      parent$entries <- c(parent$entries,list(rentry(node_box(sibling),child=sibling)))
      sibling$parent <- parent
    }
    node <- parent
  }
}
find_leaf <- function(tree,id,box) {
  pending <- list(tree$root)
  while (length(pending)) {
    node <- pending[[length(pending)]]
    pending <- head(pending,-1L)
    if (node$level == 0L) {
      index <- which(vapply(node$entries,function(entry) entry$id == id,logical(1)))
      if (length(index)) return(list(node=node,index=index[1L]))
    } else {
      for (entry in rev(node$entries)) if (contains(
          entry$box,
          box
      )) pending[[length(pending)+1L]] <- entry$child
    }
  }
  NULL
}
rtree_delete <- function(tree,point) {
  found <- find_leaf(tree,point[1L],point_box(point))
  node <- found$node
  node$entries <- node$entries[-found$index]
  removed <- list()
  while (!identical(node,tree$root)) {
    parent <- node$parent
    index <- which(vapply(parent$entries,function(entry) identical(entry$child,node),logical(1)))[1L]
    if (length(node$entries) < tree$minimum) {
      parent$entries <- parent$entries[-index]
      removed[[length(removed)+1L]] <- node
      node$parent <- NULL
    } else parent$entries[[index]]$box <- node_box(node)
    node <- parent
  }
  for (node in removed) for (entry in node$entries) rtree_insert(tree,entry,node$level)
  while (tree$root$level > 0L && length(tree$root$entries) == 1L) {
    tree$root <- tree$root$entries[[1L]]$child
    tree$root$parent <- NULL
  }
}
str_root <- function(entries,maximum) {
  numbers <- vapply(entries,function(entry) entry$id,integer(1))
  level <- 0L
  repeat {
    pages <- (length(entries)+maximum-1L) %/% maximum
    slabs <- 1L
    while (slabs*slabs < pages) slabs <- slabs+1L
    xs <- vapply(entries,function(entry) entry$box[1L]+entry$box[3L],integer(1))
    ys <- vapply(entries,function(entry) entry$box[2L]+entry$box[4L],integer(1))
    ordering <- order(xs,ys,numbers)
    nodes <- list()
    slab_size <- slabs*maximum
    for (start in seq.int(1L,length(entries),by=slab_size)) {
      indices <- ordering[seq.int(start,min(start+slab_size-1L,length(entries)))]
      indices <- indices[order(ys[indices],xs[indices],numbers[indices])]
      for (offset in seq.int(1L,length(indices),by=maximum)) {
        group <- indices[seq.int(offset,min(offset+maximum-1L,length(indices)))]
        nodes[[length(nodes)+1L]] <- rnode(level,entries[group])
      }
    }
    if (length(nodes) == 1L) return(nodes[[1L]])
    entries <- lapply(nodes,function(node) rentry(node_box(node),child=node))
    numbers <- seq_along(nodes)-1L
    level <- level+1L
  }
}
rtree_build <- function(objects,maximum,minimum,bulk=FALSE) {
  entries <- lapply(
      objects,
      function(object) rentry(if (length(object) == 3L) point_box(object) else object[-1L],id=object[1L])
  )
  tree <- new.env(parent=emptyenv())
  tree$maximum <- maximum
  tree$minimum <- minimum
  tree$root <- rnode(0L)
  if (bulk) tree$root <- str_root(entries,maximum) else for (entry in entries) rtree_insert(tree,entry)
  tree
}
