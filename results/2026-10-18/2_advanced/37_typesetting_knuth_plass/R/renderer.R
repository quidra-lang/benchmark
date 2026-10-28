display_line <- function(pieces, slack, alignment, last) {
  pieces <- gsub("~", " ", pieces, fixed = TRUE)
  text <- paste(pieces, collapse = " ")
  if (slack <= 0L) return(text)
  gaps <- length(pieces) - 1L
  if (alignment == "justify" && !last && gaps > 0L) {
    quotient <- slack %/% gaps
    remainder <- slack %% gaps
    parts <- pieces[[1L]]
    for (index in seq_len(gaps)) parts <- c(
        parts,
        strrep(" ", quotient + 1L + as.integer(index <= remainder)),
        pieces[[index + 1L]]
    )
    return(paste(parts, collapse = ""))
  }
  if (alignment == "right") return(paste0(strrep(" ", slack), text))
  if (alignment == "center") return(paste0(strrep(" ", slack %/% 2L), text))
  text
}
format_table <- function(rows, columns, caption, number) {
  alignments <- strsplit(columns, "", fixed = TRUE)[[1L]]
  widths <- vapply(
      seq_along(alignments),
      function(index) max(vapply(rows, function(row) nchar(row[[index]]), 0L)),
      0L
  )
  lines <- if (nzchar(caption)) paste0("Table ", number, ". ", caption) else character()
  for (row_index in seq_along(rows)) {
    row <- rows[[row_index]]
    cells <- vapply(seq_along(alignments), function(i) {
      missing <- widths[[i]] - nchar(row[[i]])
      before <- if (alignments[[i]] == "l") 0L else if (alignments[[i]] == "r") missing else missing %/% 2L
      paste0(strrep(" ", before), row[[i]], strrep(" ", missing - before))
    }, "")
    lines <- c(lines, sub(" +$", "", paste(cells, collapse = " | ")))
    if (row_index == 1L) lines <- c(lines, paste(strrep("-", widths), collapse = "-+-"))
  }
  lines
}
running_head <- function(fields, values, width, serial) {
  expanded <- vapply(fields, function(field) {
    for (name in names(values)) field <- gsub(paste0("{", name, "}"), values[[name]], field, fixed = TRUE)
    field
  }, "")
  if (serial %% 2L == 0L) expanded[c(1L, 3L)] <- expanded[c(3L, 1L)]
  starts <- c(0L, (width - nchar(expanded[[2L]])) %/% 2L, width - nchar(expanded[[3L]]))
  line <- rep.int(" ", width)
  for (i in seq_along(expanded)) if (nzchar(expanded[[i]])) line[seq.int(
      starts[[i]] + 1L,
      starts[[i]] + nchar(expanded[[i]])
  )] <- strsplit(expanded[[i]], "", fixed = TRUE)[[1L]]
  sub(" +$", "", paste(line, collapse = ""))
}
pages_lines <- function(pages) {
  lines <- character()
  for (page in pages) lines <- c(
      lines,
      paste0("--- page ", page$serial, " ---"),
      page$header,
      "",
      page$body,
      "",
      page$footer
  )
  lines
}
