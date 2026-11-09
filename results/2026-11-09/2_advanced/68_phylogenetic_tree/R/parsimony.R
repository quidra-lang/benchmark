merge_sets <- function(first,second) {
  common <- bitwAnd(first,second)
  if (common != 0L) c(common,0L) else c(bitwOr(first,second),1L)
}
provisional <- function(rooted,pattern) {
  sets <- integer(length(rooted$tree$adjacent))
  changes <- 0L
  for (node in rev(rooted$order)) {
    if (node <= rooted$tree$size) sets[node] <- pattern[node] else {
      children <- setdiff(rooted$children[[node]],rooted$outgroup)
      merged <- merge_sets(sets[children[1L]],sets[children[2L]])
      sets[node] <- merged[1L]
      changes <- changes+merged[2L]
      if (node == rooted$root) changes <- changes+merge_sets(sets[node],sets[rooted$outgroup])[2L]
    }
  }
  list(sets=sets,changes=changes)
}
pattern_scores <- function(tree,patterns,outgroup) {
  rooted <- root_tree(tree,outgroup)
  vapply(patterns$encoded,function(pattern) provisional(rooted,pattern)$changes,integer(1))
}
parsimony_score <- function(tree,patterns,outgroup) sum(pattern_scores(
    tree,
    patterns,
    outgroup
)*patterns$weights)
first_base <- function(mask) bitwAnd(mask,-mask)
reconstruct <- function(tree,patterns,outgroup) {
  rooted <- root_tree(tree,outgroup)
  ancestors <- setNames(
      lapply(tree_internals(tree),function(unused) character()),
      as.character(tree_internals(tree))
  )
  edges <- tree_edges(tree)
  branch_changes <- setNames(
      integer(length(edges)),
      vapply(edges,function(edge) paste(edge[1L],edge[2L],sep=","),character(1))
  )
  scores <- integer()
  for (index in seq_along(patterns$encoded)) {
    result <- provisional(rooted,patterns$encoded[[index]])
    sets <- result$sets
    scores <- c(scores,result$changes)
    combined <- merge_sets(sets[rooted$root],sets[outgroup])[1L]
    initial <- first_base(combined)
    states <- integer(length(tree$adjacent))
    for (node in c(
        rooted$root,
        outgroup
    )) states[node] <- if (bitwAnd(sets[node],initial) != 0L) initial else first_base(sets[node])
    for (node in rooted$order[-1L]) {
      if (node == outgroup) next
      parent_state <- states[rooted$parents[node]]
      states[node] <- if (bitwAnd(sets[node],parent_state) != 0L) parent_state else first_base(sets[node])
    }
    for (node in names(ancestors)) ancestors[[node]] <- c(
        ancestors[[node]],
        BASES[match(states[as.integer(node)],c(1L,2L,4L,8L))]
    )
    for (edge in edges) if (states[edge[1L]] != states[edge[2L]]) {
      key <- paste(edge[1L],edge[2L],sep=",")
      branch_changes[key] <- branch_changes[[key]]+patterns$weights[index]
    }
  }
  list(
      ancestors=lapply(ancestors,function(states) paste(states[patterns$columns],collapse="")),
      branch_changes=branch_changes,
      column_changes=scores[patterns$columns]
  )
}
branches <- function(tree,outgroup) {
  rooted <- root_tree(tree,outgroup)
  edges <- lapply(
      rooted$order[-1L],
      function(child) c(
          if (child == outgroup) rooted$ingroup else rooted$masks[child],
          rooted$parents[child],
          child
      )
  )
  edges[order(vapply(edges,function(edge) edge[1L],integer(1)))]
}
insert_taxon <- function(tree,a,b,taxon) {
  result <- copy_tree(tree)
  disconnect(result,a,b)
  node <- internal_node(result)
  result$adjacent[[taxon]] <- numeric()
  connect(result,a,node)
  connect(result,b,node)
  connect(result,taxon,node)
  result
}
nni_candidates <- function(tree,outgroup) {
  rooted <- root_tree(tree,outgroup)
  candidates <- list()
  for (edge in branches(tree,outgroup)) {
    mask <- edge[1L]
    a <- edge[2L]
    b <- edge[3L]
    if (a <= tree$size || b <= tree$size) next
    sibling <- setdiff(rooted$children[[a]],c(b,outgroup))[1L]
    children <- rooted$children[[b]]
    children <- children[order(rooted$masks[children])]
    for (swap in seq_along(children)) {
      child <- children[swap]
      result <- copy_tree(tree)
      sibling_length <- disconnect(result,a,sibling)
      child_length <- disconnect(result,b,child)
      connect(result,a,child,child_length)
      connect(result,b,sibling,sibling_length)
      candidates[[length(candidates)+1L]] <- list(mask=mask,swap=swap,tree=result)
    }
  }
  candidates
}
