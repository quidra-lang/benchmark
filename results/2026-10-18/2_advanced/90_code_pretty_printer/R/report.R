doc_tree <- function(document, depth = 0L) {
  kind <- document$kind
  prefix <- strrep("  ", depth)
  if (kind == "concat") return(unlist(lapply(document$children, doc_tree, depth = depth), use.names = FALSE))
  if (kind == "text") return(paste0(prefix, 'text "', document$value, '"'))
  if (kind == "suffix") return(paste0(prefix, 'suffix "', document$value, '"'))
  if (kind == "if_break") return(paste0(prefix, 'if_break "', document$broken, '" "', document$flat, '"'))
  if (kind %in% c("group", "nest", "align")) {
    label <- if (kind == "group") paste("group", document$mode) else if (kind == "nest") paste("nest", document$amount) else "align"
    return(c(paste0(prefix, label), doc_tree(document$children[[1L]], depth + 1L)))
  }
  paste0(prefix, kind)
}
diff_lines <- function(original, formatted) {
  n <- length(original)
  m <- length(formatted)
  table <- matrix(0L, n + 1L, m + 1L)
  for (i in rev(seq_len(n))) for (j in rev(seq_len(m))) {
    table[i, j] <- if (original[[i]] == formatted[[j]]) table[i + 1L, j + 1L] + 1L else max(table[i + 1L, j], table[i, j + 1L])
  }
  i <- j <- 1L
  deleted <- inserted <- 0L
  hunks <- list()
  current <- NULL
  while (i <= n || j <= m) {
    if (i <= n && j <= m && original[[i]] == formatted[[j]]) {
      if (!is.null(current)) hunks[[length(hunks) + 1L]] <- current
      current <- NULL
      i <- i + 1L
      j <- j + 1L
      next
    }
    if (is.null(current)) current <- list(start_old = i - 1L, start_new = j - 1L, deletes = 0L, inserts = 0L, lines = character())
    if (j > m || (i <= n && table[i + 1L, j] >= table[i, j + 1L])) {
      current$deletes <- current$deletes + 1L
      deleted <- deleted + 1L
      current$lines <- c(current$lines, paste0("-", original[[i]]))
      i <- i + 1L
    } else {
      current$inserts <- current$inserts + 1L
      inserted <- inserted + 1L
      current$lines <- c(current$lines, paste0("+", formatted[[j]]))
      j <- j + 1L
    }
  }
  if (!is.null(current)) hunks[[length(hunks) + 1L]] <- current
  result <- sprintf("hunks=%d deleted=%d inserted=%d", length(hunks), deleted, inserted)
  for (hunk in hunks) {
    d <- hunk$deletes
    e <- hunk$inserts
    a <- hunk$start_old + as.integer(d > 0L)
    b <- hunk$start_new + as.integer(e > 0L)
    result <- c(result, sprintf("@@ -%d,%d +%d,%d @@", a, d, b, e), hunk$lines)
  }
  result
}
write_lines <- function(name, lines) {
  dir.create("output", showWarnings = FALSE)
  connection <- file(file.path("output", name), open = "wb")
  on.exit(close(connection))
  if (length(lines)) writeChar(paste0(paste(lines, collapse = "\n"), "\n"), connection, eos = NULL, useBytes = TRUE)
}
