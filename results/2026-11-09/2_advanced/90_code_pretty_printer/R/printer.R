print_command <- function(indentation, mode, document) list(indentation = indentation, mode = mode, document = document)
fits <- function(remaining, candidate, rest) {
  if (remaining < 0L) return(FALSE)
  check <- list(candidate)
  next_existing <- length(rest)
  repeat {
    if (!length(check)) {
      if (!next_existing) return(TRUE)
      check <- list(rest[[next_existing]])
      next_existing <- next_existing - 1L
    }
    command <- check[[length(check)]]
    check <- head(check, -1L)
    indentation <- command$indentation
    mode <- command$mode
    document <- command$document
    kind <- document$kind
    if (kind == "text") {
      remaining <- remaining - nchar(document$value)
    } else if (kind == "if_break") {
      remaining <- remaining - nchar(if (mode == "break") document$broken else document$flat)
    } else if (kind == "line") {
      if (mode == "break") return(TRUE)
      remaining <- remaining - 1L
    } else if (kind == "softline") {
      if (mode == "break") return(TRUE)
    } else if (kind == "hardline") {
      return(TRUE)
    } else if (kind == "concat") {
      for (child in rev(document$children)) check[[length(check) + 1L]] <- print_command(indentation, mode, child)
    } else if (kind == "group") {
      check[[length(check) + 1L]] <- print_command(indentation, if (document$forced) "break" else mode, document$children[[1L]])
    } else if (kind %in% c("nest", "align")) {
      check[[length(check) + 1L]] <- print_command(indentation, mode, document$children[[1L]])
    }
    if (remaining < 0L) return(FALSE)
  }
}
print_document <- function(document, profile) {
  width <- profile$width
  column <- profile$comment_column
  result <- pending <- character()
  current <- ""
  stack <- list(print_command(0L, "break", document))
  finalize <- function() {
    output <- trim_spaces(current)
    if (length(pending)) {
      comment_text <- paste(pending, collapse = " ")
      if (column > 0L && nchar(output) < column - 1L && column - 1L + nchar(comment_text) <= width) {
        output <- paste0(output, strrep(" ", column - 1L - nchar(output)), comment_text)
      } else {
        output <- paste0(output, " ", comment_text)
      }
      pending <<- character()
    }
    result <<- c(result, output)
  }
  while (length(stack)) {
    command <- stack[[length(stack)]]
    stack <- head(stack, -1L)
    indentation <- command$indentation
    mode <- command$mode
    document <- command$document
    kind <- document$kind
    if (kind == "text") {
      current <- paste0(current, document$value)
    } else if (kind == "if_break") {
      current <- paste0(current, if (mode == "break") document$broken else document$flat)
    } else if (kind %in% c("line", "softline", "hardline")) {
      if (kind == "hardline" || mode == "break") {
        finalize()
        current <- strrep(" ", indentation)
      } else if (kind == "line") {
        current <- paste0(current, " ")
      }
    } else if (kind == "concat") {
      for (child in rev(document$children)) stack[[length(stack) + 1L]] <- print_command(indentation, mode, child)
    } else if (kind == "nest") {
      stack[[length(stack) + 1L]] <- print_command(indentation + document$amount, mode, document$children[[1L]])
    } else if (kind == "align") {
      stack[[length(stack) + 1L]] <- print_command(nchar(current), mode, document$children[[1L]])
    } else if (kind == "suffix") {
      pending <- c(pending, document$value)
    } else if (kind == "group") {
      next_mode <- if (mode == "flat") "flat" else if (document$forced) "forced" else if (fits(width - nchar(current), print_command(indentation, "flat", document$children[[1L]]), stack)) "flat" else "break"
      document$mode <- next_mode
      stack[[length(stack) + 1L]] <- print_command(indentation, if (next_mode == "flat") "flat" else "break", document$children[[1L]])
    }
  }
  finalize()
  result
}
