one_smaller_subsets <- function(itemset) lapply(seq_along(itemset), function(index) itemset[-index])

generate_candidates <- function(previous, size, taxonomy = NULL) {
  previous <- previous[order(vapply(previous, itemset_text, character(1L)), method = "radix")]
  known <- vapply(previous, itemset_text, character(1L))
  candidates <- list()
  joined <- excluded <- pruned <- 0L
  for (first in seq_along(previous)) {
    if (first == length(previous)) next
    for (second in seq.int(first + 1L, length(previous))) {
      a <- previous[[first]]
      b <- previous[[second]]
      if (!identical(head(a, -1L), head(b, -1L))) break
      joined <- joined + 1L
      candidate <- c(a, tail(b, 1L))
      if (!is.null(taxonomy) && size == 2L &&
          (any(unname(taxonomy[candidate[1L]]) == candidate[2L], na.rm = TRUE) ||
           any(unname(taxonomy[candidate[2L]]) == candidate[1L], na.rm = TRUE))) {
        excluded <- excluded + 1L
      } else if (any(!vapply(one_smaller_subsets(candidate), itemset_text, character(1L)) %in% known)) {
        pruned <- pruned + 1L
      } else candidates[[length(candidates) + 1L]] <- candidate
    }
  }
  list(joined = joined, excluded = excluded, pruned = pruned, itemsets = candidates)
}

count_supports <- function(baskets, candidates) {
  index <- new.env(hash = TRUE, parent = emptyenv())
  for (number in seq_along(baskets)) for (item in baskets[[number]]) {
    index[[item]] <- c(index[[item]], number)
  }
  counts <- vapply(candidates, function(candidate) {
    if (!length(candidate)) return(as.numeric(length(baskets)))
    found <- index[[candidate[1L]]]
    if (length(candidate) > 1L) for (item in candidate[-1L]) found <- intersect(found, index[[item]])
    as.numeric(length(found))
  }, numeric(1L))
  names(counts) <- vapply(candidates, itemset_text, character(1L))
  counts
}
