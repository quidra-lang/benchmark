disjoint_sets <- function(n) {
  sets <- new.env(parent=emptyenv())
  sets$parent <- seq_len(n)
  sets$size <- rep(1L,n)
  sets$count <- n
  sets
}
find_root <- function(sets,site) {
  while (sets$parent[site] != site) {
    sets$parent[site] <- sets$parent[sets$parent[site]]
    site <- sets$parent[site]
  }
  site
}
unite <- function(sets,a,b) {
  a <- find_root(sets,a)
  b <- find_root(sets,b)
  if (a == b) return(FALSE)
  if (sets$size[a] < sets$size[b]) {
    temporary <- a
    a <- b
    b <- temporary
  }
  sets$parent[b] <- a
  sets$size[a] <- sets$size[a]+sets$size[b]
  sets$count <- sets$count-1L
  TRUE
}
nearest_neighbors <- function(points,neighbors) vapply(seq_along(points),function(s) {
  candidates <- neighbors[[s]]
  distances <- vapply(candidates,function(t) d2(points[[s]],points[[t]]),numeric(1))
  candidates[order(distances,candidates)[1L]]
},integer(1))
nearest_components <- function(nearest) {
  sets <- disjoint_sets(length(nearest))
  for (s in seq_along(nearest)) unite(sets,s,nearest[s])
  groups <- split(seq_along(nearest),vapply(seq_along(nearest),function(s) find_root(sets,s),integer(1)))
  unname(groups[order(vapply(groups,min,integer(1)))])
}
kruskal <- function(points,edges) {
  sets <- disjoint_sets(length(points))
  lengths <- vapply(edges,function(edge) d2(points[[edge[1L]]],points[[edge[2L]]]),numeric(1))
  first <- vapply(edges,`[`,integer(1),1L)
  second <- vapply(edges,`[`,integer(1),2L)
  adopted <- list()
  for (i in order(lengths,first,second)) {
    edge <- edges[[i]]
    if (unite(sets,edge[1L],edge[2L])) {
      adopted[[length(adopted)+1L]] <- edge
      if (sets$count == 1L) break
    }
  }
  adopted
}
is_gabriel <- function(points,edge,directed) {
  a <- edge[1L]
  b <- edge[2L]
  for (q in c(directed[a,b],directed[b,a])) if (q != 0L && dot_at(
      points[[q]],
      points[[a]],
      points[[b]]
  ) <= 0) return(FALSE)
  TRUE
}
is_relative_neighbor <- function(points,edge) {
  a <- points[[edge[1L]]]
  b <- points[[edge[2L]]]
  length2 <- d2(a,b)
  !any(vapply(points,function(p) d2(a,p) < length2 && d2(b,p) < length2,logical(1)))
}
greedy_route <- function(points,neighbors,start,target) {
  path <- start
  total <- 0
  while (tail(path,1L) != target) {
    current <- tail(path,1L)
    candidates <- neighbors[[current]]
    lengths <- vapply(candidates,function(s) d2(points[[s]],points[[target]]),numeric(1))
    following <- candidates[order(lengths,candidates)[1L]]
    total <- total+sqrt(d2(points[[current]],points[[following]]))
    path <- c(path,following)
  }
  list(path=path,length=total)
}
dijkstra <- function(points,neighbors,start) {
  n <- length(points)
  distances <- rep(Inf,n)
  previous <- integer(n)
  done <- logical(n)
  distances[start] <- 0
  for (unused in seq_len(n)) {
    candidates <- which(!done)
    site <- candidates[which.min(distances[candidates])]
    if (!length(site) || !is.finite(distances[site])) break
    done[site] <- TRUE
    for (other in neighbors[[site]]) {
      candidate <- distances[site]+sqrt(d2(points[[site]],points[[other]]))
      if (candidate < distances[other]) {
        distances[other] <- candidate
        previous[other] <- site
      }
    }
  }
  list(distances=distances,previous=previous)
}
