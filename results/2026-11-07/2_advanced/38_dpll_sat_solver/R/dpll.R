run_round <- function(variable_count, search_clauses) {
  clauses <- lapply(search_clauses, identity)
  assignment <- integer(variable_count)
  watches <- new.env(hash = TRUE, parent = emptyenv())
  trail <- list()
  queue_head <- 1L
  trace <- character()
  stats <- setNames(integer(4L), c("decisions", "propagations", "conflicts", "max_depth"))
  value <- function(literal) if (literal > 0L) assignment[[abs(literal)]] else -assignment[[abs(literal)]]
  assign_literal <- function(literal, kind) {
    assignment[[abs(literal)]] <<- if (literal > 0L) 1L else -1L
    trail[[length(trail) + 1L]] <<- list(literal = literal, kind = kind)
    trace <<- c(trace, paste0(kind, literal))
  }
  conflict <- function() {
    stats[["conflicts"]] <<- stats[["conflicts"]] + 1L
    trace <<- c(trace, "C")
  }
  for (index in seq_along(clauses)) {
    clause <- clauses[[index]]
    if (length(clause) >= 2L) {
      for (literal in clause[1L:2L]) {
        key <- as.character(literal)
        previous <- if (exists(key, envir = watches, inherits = FALSE)) watches[[key]] else integer()
        watches[[key]] <- c(previous, index)
      }
    }
  }
  for (clause in clauses) {
    if (!length(clause)) {
      conflict()
      return(list(model = NULL, trace = trace, stats = stats))
    }
    if (length(clause) == 1L) {
      literal <- clause[[1L]]
      truth <- value(literal)
      if (truth == -1L) {
        conflict()
        return(list(model = NULL, trace = trace, stats = stats))
      }
      if (truth == 0L) {
        assign_literal(literal, "P")
        stats[["propagations"]] <- stats[["propagations"]] + 1L
      }
    }
  }
  repeat {
    found_conflict <- FALSE
    while (queue_head <= length(trail)) {
      true_literal <- trail[[queue_head]]$literal
      queue_head <- queue_head + 1L
      false_literal <- -true_literal
      false_key <- as.character(false_literal)
      watch_list <- if (exists(
          false_key,
          envir = watches,
          inherits = FALSE
      )) watches[[false_key]] else integer()
      index <- 1L
      while (index <= length(watch_list)) {
        clause_id <- watch_list[[index]]
        clause <- clauses[[clause_id]]
        if (clause[[1L]] == false_literal) clause[1L:2L] <- clause[2L:1L]
        other <- clause[[1L]]
        clauses[[clause_id]] <- clause
        if (value(other) == 1L) {
          index <- index + 1L
          next
        }
        substitute <- NULL
        if (length(clause) >= 3L) {
          for (j in seq.int(3L, length(clause))) {
            if (value(clause[[j]]) != -1L) {
              substitute <- j
              break
            }
          }
        }
        if (!is.null(substitute)) {
          clause[c(2L, substitute)] <- clause[c(substitute, 2L)]
          clauses[[clause_id]] <- clause
          watch_list <- watch_list[-index]
          key <- as.character(clause[[2L]])
          previous <- if (exists(key, envir = watches, inherits = FALSE)) watches[[key]] else integer()
          watches[[key]] <- c(previous, clause_id)
          next
        }
        truth <- value(other)
        if (truth == -1L) {
          conflict()
          found_conflict <- TRUE
          break
        }
        if (truth == 0L) {
          assign_literal(other, "P")
          stats[["propagations"]] <- stats[["propagations"]] + 1L
        }
        index <- index + 1L
      }
      watches[[false_key]] <- watch_list
      if (found_conflict) break
    }
    if (found_conflict) {
      while (length(trail) && tail(trail, 1L)[[1L]]$kind != "D") {
        literal <- tail(trail, 1L)[[1L]]$literal
        trail <- head(trail, -1L)
        assignment[[abs(literal)]] <- 0L
      }
      if (!length(trail)) return(list(model = NULL, trace = trace, stats = stats))
      decision <- tail(trail, 1L)[[1L]]$literal
      trail <- head(trail, -1L)
      assignment[[abs(decision)]] <- 0L
      assign_literal(-decision, "F")
      queue_head <- length(trail)
      next
    }
    counts <- integer(2L * variable_count)
    for (clause in clauses) {
      if (any(vapply(clause, function(literal) value(literal) == 1L, FALSE))) next
      for (literal in clause) {
        if (value(literal) == 0L) {
          index <- 2L * abs(literal) - as.integer(literal > 0L)
          counts[[index]] <- counts[[index]] + 1L
        }
      }
    }
    if (!any(counts > 0L)) return(list(model = assignment == 1L, trace = trace, stats = stats))
    index <- which.max(counts)
    best <- (index + 1L) %/% 2L
    if (index %% 2L == 0L) best <- -best
    assign_literal(best, "D")
    stats[["decisions"]] <- stats[["decisions"]] + 1L
    depth <- sum(vapply(trail, function(entry) entry$kind %in% c("D", "F"), FALSE))
    stats[["max_depth"]] <- max(stats[["max_depth"]], depth)
  }
}
