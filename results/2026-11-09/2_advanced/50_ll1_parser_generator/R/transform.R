clone_grammar <- function(grammar) list(order=grammar$order,rules=grammar$rules,start=grammar$start)
fresh_name <- function(symbol,rules) {
  proposed <- paste0(substr(symbol,1L,nchar(symbol)-1L),"'>")
  while (proposed %in% names(rules)) proposed <- paste0(substr(proposed,1L,nchar(proposed)-1L),"'>")
  proposed
}
leading_reaches <- function(rules,source,target) {
  queue <- seen <- source
  cursor <- 1L
  while (cursor <= length(queue)) {
    current <- queue[cursor]
    cursor <- cursor+1L
    for (row in rules[[current]]) {
      if (!length(row) || !is_nonterminal(row[1L])) next
      next_symbol <- row[1L]
      if (next_symbol == target) return(TRUE)
      if (!next_symbol %in% seen) {
        seen <- c(seen,next_symbol)
        queue <- c(queue,next_symbol)
      }
    }
  }
  FALSE
}
eliminate_left_recursion <- function(grammar) {
  g <- clone_grammar(grammar)
  initial <- g$order
  log <- character()
  for (i in seq_along(initial)) {
    lhs <- initial[i]
    for (earlier in head(initial,i-1L)) {
      current <- g$rules[[lhs]]
      if (any(vapply(
          current,
          function(row) length(row) > 0L && row[1L] == earlier,
          logical(1)
      )) && leading_reaches(g$rules,earlier,lhs)) {
        replacements <- list()
        for (row in current) {
          if (length(row) && row[1L] == earlier) {
            replacements <- c(replacements,lapply(g$rules[[earlier]],function(source) c(source,row[-1L])))
          } else replacements[[length(replacements)+1L]] <- row
        }
        g$rules[[lhs]] <- unique(replacements)
        log <- c(log,paste("substitute",earlier,"into",lhs))
      }
    }
    source <- list()
    for (row in g$rules[[lhs]]) {
      if (identical(row,lhs)) log <- c(
          log,
          paste("remove cycle",lhs,"->",lhs)
      ) else source[[length(source)+1L]] <- row
    }
    recursive <- lapply(
        Filter(function(row) length(row) > 0L && row[1L] == lhs,source),
        function(row) row[-1L]
    )
    if (!length(recursive)) {
      g$rules[[lhs]] <- source
    } else {
      ordinary <- Filter(function(row) !length(row) || row[1L] != lhs,source)
      created <- fresh_name(lhs,g$rules)
      g$rules[[lhs]] <- lapply(ordinary,function(row) c(row,created))
      g$rules[[created]] <- c(lapply(recursive,function(row) c(row,created)),list(character()))
      position <- match(lhs,g$order)
      g$order <- append(g$order,created,after=position)
      log <- c(log,paste("eliminate left recursion in",lhs,"with",created))
    }
  }
  list(grammar=g,log=log)
}
left_factor <- function(grammar) {
  g <- clone_grammar(grammar)
  log <- character()
  position <- 1L
  while (position <= length(g$order)) {
    lhs <- g$order[position]
    current <- g$rules[[lhs]]
    insertions <- character()
    index <- 1L
    while (index <= length(current)) {
      row <- current[[index]]
      if (!length(row)) {
        index <- index+1L
        next
      }
      group <- which(vapply(current,function(other) length(other) > 0L && other[1L] == row[1L],logical(1)))
      if (length(group) == 1L) {
        index <- index+1L
        next
      }
      limit <- min(lengths(current[group]))
      prefix_length <- 0L
      while (prefix_length < limit && all(vapply(
          current[group],
          function(other) other[prefix_length+1L] == row[prefix_length+1L],
          logical(1)
      ))) prefix_length <- prefix_length+1L
      prefix <- head(row,prefix_length)
      created <- fresh_name(lhs,g$rules)
      g$rules[[created]] <- lapply(current[group],function(other) tail(other,length(other)-prefix_length))
      alternatives <- list()
      for (i in seq_along(current)) {
        if (i == group[1L]) alternatives[[length(alternatives)+1L]] <- c(prefix,created) else
          if (!i %in% group) alternatives[[length(alternatives)+1L]] <- current[[i]]
      }
      current <- alternatives
      g$rules[[lhs]] <- current
      insertions <- c(insertions,created)
      log <- c(log,paste("left factor",lhs,"on",format_alternative(prefix),"with",created))
      index <- group[1L]+1L
    }
    g$order <- append(g$order,insertions,after=position)
    position <- position+1L
  }
  list(grammar=g,log=log)
}
