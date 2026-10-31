terminal_order <- function(terms) c(
    sort(setdiff(unique(terms),END_MARKER),method="radix"),
    if (END_MARKER %in% terms) END_MARKER else character()
)
terminals_of <- function(grammar) {
  symbols <- unique(unlist(grammar$rules[grammar$order],use.names=FALSE))
  symbols[!vapply(symbols,is_nonterminal,logical(1))]
}
first_sequence <- function(rhs,nullable,first) {
  found <- character()
  for (symbol in rhs) {
    if (!is_nonterminal(symbol)) return(list(first=union(found,symbol),empty=FALSE))
    found <- union(found,first[[symbol]])
    if (!nullable[[symbol]]) return(list(first=found,empty=FALSE))
  }
  list(first=found,empty=TRUE)
}
analyze_sets <- function(grammar) {
  order <- grammar$order
  nullable <- setNames(as.list(rep(FALSE,length(order))),order)
  first <- follow <- setNames(replicate(length(order),character(),simplify=FALSE),order)
  follow[[grammar$start]] <- END_MARKER
  passes <- list()
  for (kind in c("nullable","first","follow")) {
    count <- 0L
    repeat {
      count <- count+1L
      changed <- FALSE
      for (lhs in order) {
        if (kind == "nullable") {
          if (!nullable[[lhs]] && any(vapply(grammar$rules[[lhs]],function(rhs) all(vapply(rhs,function(symbol)
              is_nonterminal(symbol) && nullable[[symbol]],logical(1))),logical(1)))) {
            nullable[[lhs]] <- TRUE
            changed <- TRUE
          }
        } else for (rhs in grammar$rules[[lhs]]) {
          if (kind == "first") {
            more <- first_sequence(rhs,nullable,first)$first
            if (any(!more %in% first[[lhs]])) {
              first[[lhs]] <- union(first[[lhs]],more)
              changed <- TRUE
            }
          } else for (i in seq_along(rhs)) {
            symbol <- rhs[i]
            if (!is_nonterminal(symbol)) next
            suffix <- tail(rhs,length(rhs)-i)
            result <- first_sequence(suffix,nullable,first)
            more <- if (result$empty) union(result$first,follow[[lhs]]) else result$first
            if (any(!more %in% follow[[symbol]])) {
              follow[[symbol]] <- union(follow[[symbol]],more)
              changed <- TRUE
            }
          }
        }
      }
      if (!changed) break
    }
    passes[[kind]] <- count
  }
  list(
      nullable=nullable,
      first=first,
      follow=follow,
      passes=passes,
      terminals=terminal_order(terminals_of(grammar))
  )
}
