cell_key <- function(lhs,token) paste(lhs,token,sep="\t")
number_productions <- function(grammar) {
  productions <- list()
  for (lhs in grammar$order) for (rhs in grammar$rules[[lhs]]) productions[[length(productions)+1L]] <-
    list(
        number=length(productions)+1L,
        lhs=lhs,
        rhs=rhs,
        notation=format_production(lhs,rhs),
        predict=character()
    )
  productions
}
build_table <- function(grammar,sets) {
  productions <- number_productions(grammar)
  tokens <- c(sets$terminals,END_MARKER)
  keys <- unlist(
      lapply(grammar$order,function(lhs) vapply(tokens,function(token) cell_key(lhs,token),character(1))),
      use.names=FALSE
  )
  cells <- setNames(replicate(length(keys),integer(),simplify=FALSE),keys)
  choices <- setNames(integer(length(keys)),keys)
  for (i in seq_along(productions)) {
    p <- productions[[i]]
    result <- first_sequence(p$rhs,sets$nullable,sets$first)
    predicts <- setNames(rep("FIRST",length(result$first)),result$first)
    if (result$empty) for (token in sets$follow[[p$lhs]]) if (!token %in% names(predicts)) predicts[token] <- "FOLLOW"
    productions[[i]]$predict <- predicts
    for (token in terminal_order(names(predicts))) {
      key <- cell_key(p$lhs,token)
      cells[[key]] <- c(cells[[key]],i)
    }
  }
  conflicts <- list()
  for (lhs in grammar$order) for (token in tokens) {
    key <- cell_key(lhs,token)
    entries <- cells[[key]]
    if (!length(entries)) next
    reasons <- vapply(productions[entries],function(p) p$predict[[token]],character(1))
    preferred <- which(reasons == "FIRST")
    choice <- entries[if (length(preferred)) preferred[1L] else 1L]
    choices[key] <- choice
    if (length(entries) >= 2L) {
      kind <- if (all(reasons == "FIRST")) "FIRST/FIRST" else if (all(reasons == "FOLLOW")) "FOLLOW/FOLLOW" else "FIRST/FOLLOW"
      conflicts[[length(conflicts)+1L]] <- list(lhs=lhs,token=token,kind=kind,entries=entries,chosen=choice)
    }
  }
  list(productions=productions,cells=cells,choices=choices,conflicts=conflicts)
}
