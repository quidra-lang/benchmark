preprocess <- function(variables, original, use_pure) {
  working <- list()
  records <- setNames(rep(list(integer()), 4L), c("tautology", "unit", "subsumed", "pure"))
  counts <- setNames(
      integer(7L),
      c(
          "tautologies",
          "duplicate_literals",
          "unit_fixed",
          "unit_removed",
          "subsumed",
          "pure_fixed",
          "pure_removed"
      )
  )
  fixed <- integer(variables)
  for (number in seq_along(original)) {
    clause <- original[[number]]
    if (any(-clause %in% clause)) {
      counts[["tautologies"]] <- counts[["tautologies"]] + 1L
      records$tautology <- c(records$tautology, number)
      next
    }
    reduced <- unique(clause)
    counts[["duplicate_literals"]] <- counts[["duplicate_literals"]] + length(clause) - length(reduced)
    working[[length(working) + 1L]] <- list(number = number, clause = reduced)
  }
  empty_clause <- NULL
  repeat {
    empty <- which(vapply(working, function(pair) !length(pair$clause), FALSE))
    if (length(empty)) {
      empty_clause <- working[[empty[[1L]]]]$number
      break
    }
    units <- which(vapply(working, function(pair) length(pair$clause) == 1L, FALSE))
    if (!length(units)) break
    unit <- working[[units[[1L]]]]$clause[[1L]]
    fixed[[abs(unit)]] <- if (unit > 0L) 1L else -1L
    counts[["unit_fixed"]] <- counts[["unit_fixed"]] + 1L
    surviving <- list()
    for (pair in working) {
      if (unit %in% pair$clause) {
        records$unit <- c(records$unit, pair$number)
        counts[["unit_removed"]] <- counts[["unit_removed"]] + 1L
      } else surviving[[length(surviving) + 1L]] <- list(
          number = pair$number,
          clause = pair$clause[pair$clause != -unit]
      )
    }
    working <- surviving
  }
  if (is.null(empty_clause)) {
    before <- working
    removed <- logical(length(before))
    for (ib in seq_along(before)) {
      b <- before[[ib]]$clause
      for (ia in seq_along(before)) {
        if (ia == ib) next
        a <- before[[ia]]$clause
        if (all(a %in% b) && (length(a) < length(b) || ia < ib)) {
          removed[[ib]] <- TRUE
          break
        }
      }
    }
    working <- before[!removed]
    records$subsumed <- vapply(before[removed], `[[`, 0L, "number")
    counts[["subsumed"]] <- sum(removed)
    if (use_pure) {
      repeat {
        present <- unique(unlist(lapply(working, `[[`, "clause"), use.names = FALSE))
        pure <- present[!(-present %in% present)]
        if (!length(pure)) break
        fixed[abs(pure)] <- ifelse(pure > 0L, 1L, -1L)
        counts[["pure_fixed"]] <- counts[["pure_fixed"]] + length(pure)
        remaining <- list()
        for (pair in working) {
          if (any(pair$clause %in% pure)) {
            records$pure <- c(records$pure, pair$number)
            counts[["pure_removed"]] <- counts[["pure_removed"]] + 1L
          } else remaining[[length(remaining) + 1L]] <- pair
        }
        working <- remaining
      }
    }
  }
  counts[["removed"]] <- sum(counts[c("tautologies", "unit_removed", "subsumed", "pure_removed")])
  list(clauses = lapply(working, `[[`, "clause"), fixed = fixed, active = which(fixed == 0L), counts = counts,
       records = lapply(records, sort), empty_clause = empty_clause, pure = use_pure)
}
