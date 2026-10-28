new_tree <- function(n,taxa) {
  adjacent <- vector("list",n)
  for (taxon in taxa) adjacent[[taxon]] <- numeric()
  list2env(list(size=n,adjacent=adjacent,next_node=n+1L,negative=0L),parent=emptyenv())
}
internal_node <- function(tree) {
  node <- tree$next_node
  tree$next_node <- tree$next_node+1L
  tree$adjacent[[node]] <- numeric()
  node
}
connect <- function(tree,a,b,length=0) {
  if (is.null(tree$adjacent[[a]])) tree$adjacent[[a]] <- numeric()
  if (is.null(tree$adjacent[[b]])) tree$adjacent[[b]] <- numeric()
  tree$adjacent[[a]][as.character(b)] <- length
  tree$adjacent[[b]][as.character(a)] <- length
}
disconnect <- function(tree,a,b) {
  length <- tree$adjacent[[a]][[as.character(b)]]
  tree$adjacent[[a]] <- tree$adjacent[[a]][names(tree$adjacent[[a]]) != as.character(b)]
  tree$adjacent[[b]] <- tree$adjacent[[b]][names(tree$adjacent[[b]]) != as.character(a)]
  length
}
copy_tree <- function(tree) list2env(as.list(tree),parent=emptyenv())
tree_nodes <- function(tree) which(!vapply(tree$adjacent,is.null,logical(1)))
tree_taxa <- function(tree) tree_nodes(tree)[tree_nodes(tree) <= tree$size]
tree_internals <- function(tree) tree_nodes(tree)[tree_nodes(tree) > tree$size]
tree_edges <- function(tree) {
  edges <- list()
  for (a in tree_nodes(tree)) for (b in sort(as.integer(names(tree$adjacent[[a]])))) if (a < b) edges[[length(edges)+1L]] <- c(
      a,
      b,
      tree$adjacent[[a]][[as.character(b)]]
  )
  edges
}
root_tree <- function(tree,outgroup) {
  root <- as.integer(names(tree$adjacent[[outgroup]])[1L])
  parents <- masks <- integer(length(tree$adjacent))
  children <- vector("list",length(tree$adjacent))
  order <- integer()
  visit <- function(node,parent) {
    parents[node] <<- parent
    order <<- c(order,node)
    descendants <- sort(setdiff(as.integer(names(tree$adjacent[[node]])),parent))
    children[[node]] <<- descendants
    mask <- if (node <= tree$size) bitwShiftL(1L,node-1L) else 0L
    for (child in descendants) {
      visit(child,node)
      mask <- bitwOr(mask,masks[child])
    }
    masks[node] <<- mask
  }
  visit(root,0L)
  list(
      tree=tree,
      outgroup=outgroup,
      root=root,
      parents=parents,
      children=children,
      masks=masks,
      order=order,
      ingroup=bitwXor(masks[root],bitwShiftL(1L,outgroup-1L))
  )
}
split_set <- function(rooted) unique(rooted$masks[setdiff(tree_internals(rooted$tree),rooted$root)])
branch_lengths <- function(rooted) {
  lengths <- numeric()
  for (node in rooted$order[-1L]) {
    mask <- if (node == rooted$outgroup) rooted$ingroup else rooted$masks[node]
    lengths[as.character(mask)] <- rooted$tree$adjacent[[node]][[as.character(rooted$parents[node])]]
  }
  lengths
}
star_tree <- function(n,taxa) {
  tree <- new_tree(n,taxa)
  root <- internal_node(tree)
  for (taxon in taxa) connect(tree,root,taxon)
  tree
}
neighbor_joining <- function(matrix,taxa) {
  active <- as.integer(taxa)
  tree <- new_tree(nrow(matrix),active)
  distances <- matrix(0,2L*nrow(matrix),2L*nrow(matrix))
  distances[active,active] <- matrix[active,active,drop=FALSE]
  while (length(active) >= 4L) {
    n <- length(active)
    totals <- setNames(vapply(active,function(a) {
      total <- 0
      for (b in active) if (b != a) total <- total+distances[a,b]
      total
    },numeric(1)),as.character(active))
    best <- Inf
    selected <- integer(2L)
    for (i in seq_len(n-1L)) for (j in seq.int(i+1L,n)) {
      a <- active[i]
      b <- active[j]
      value <- (n-2L)*distances[a,b]-totals[[as.character(a)]]-totals[[as.character(b)]]
      if (value < best) {
        best <- value
        selected <- c(a,b)
      }
    }
    a <- selected[1L]
    b <- selected[2L]
    node <- internal_node(tree)
    distance <- distances[a,b]
    first_length <- distance/2+(totals[[as.character(a)]]-totals[[as.character(b)]])/(2L*(n-2L))
    connect(tree,a,node,first_length)
    connect(tree,b,node,distance-first_length)
    remaining <- active[active != a & active != b]
    for (other in remaining) distances[node,other] <- distances[
        other,
        node
    ] <- (distances[a,other]+distances[b,other]-distance)/2
    active <- c(remaining,node)
  }
  a <- active[1L]
  b <- active[2L]
  c <- active[3L]
  node <- internal_node(tree)
  ab <- distances[a,b]
  ac <- distances[a,c]
  bc <- distances[b,c]
  connect(tree,a,node,(ab+ac-bc)/2)
  connect(tree,b,node,(ab+bc-ac)/2)
  connect(tree,c,node,(ac+bc-ab)/2)
  for (edge in tree_edges(tree)) if (edge[3L] < 0) {
    connect(tree,edge[1L],edge[2L],0)
    tree$negative <- tree$negative+1L
  }
  tree
}
path_distances <- function(tree,start,unit=FALSE) {
  distances <- numeric(length(tree$adjacent))
  stack <- list(c(start,0L))
  while (length(stack)) {
    entry <- stack[[length(stack)]]
    stack <- head(stack,-1L)
    node <- entry[1L]
    parent <- entry[2L]
    for (neighbor in sort(as.integer(names(tree$adjacent[[node]])))) if (neighbor != parent) {
      distances[neighbor] <- distances[node]+if (unit) 1 else tree$adjacent[[node]][[as.character(neighbor)]]
      stack[[length(stack)+1L]] <- c(neighbor,node)
    }
  }
  distances
}
patristic_matrix <- function(tree) {
  matrix <- matrix(0,tree$size,tree$size)
  taxa <- tree_taxa(tree)
  for (i in seq_along(taxa)) {
    a <- taxa[i]
    distances <- path_distances(tree,a)
    if (i < length(taxa)) for (b in taxa[seq.int(
        i+1L,
        length(taxa)
    )]) matrix[a,b] <- matrix[b,a] <- distances[b]
  }
  matrix
}
