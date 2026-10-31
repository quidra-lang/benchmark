build_sequence <- function(blocks, orphan_lines, widow_lines) {
  lines <- boundaries <- list()
  for (index in seq_along(blocks)) {
    block <- blocks[[index]]
    start <- length(lines)
    lines <- c(lines, block$lines)
    count <- length(block$lines)
    if (block$kind == "flow" && count > 1L) {
      for (kept in seq_len(count - 1L)) {
        if (kept >= orphan_lines && count - kept >= widow_lines) boundaries[[length(boundaries) + 1L]] <- list(
            stop = start + kept,
            next_start = start + kept,
            forced = FALSE
        )
      }
    }
    if (index == length(blocks)) {
      boundaries[[length(boundaries) + 1L]] <- list(
          stop = length(lines),
          next_start = length(lines),
          forced = TRUE
      )
      next
    }
    following <- blocks[[index + 1L]]
    stop <- length(lines)
    if (!(block$list && following$list)) lines[[length(lines) + 1L]] <- text_line("")
    forced <- following$page_break
    if (forced || block$kind != "heading") boundaries[[length(boundaries) + 1L]] <- list(
        stop = stop,
        next_start = length(lines),
        forced = forced
    )
  }
  list(lines = lines, boundaries = boundaries)
}
choose_pages <- function(blocks, footnote_heights, height, orphan_lines, widow_lines) {
  sequence <- build_sequence(blocks, orphan_lines, widow_lines)
  lines <- sequence$lines
  boundaries <- sequence$boundaries
  pages <- list()
  start <- 0L
  first_boundary <- 1L
  while (start < length(lines)) {
    notes <- integer()
    note_height <- 0L
    scanned <- start
    chosen <- NULL
    for (index in seq.int(first_boundary, length(boundaries))) {
      boundary <- boundaries[[index]]
      stop <- boundary$stop
      while (scanned < stop) {
        for (number in lines[[scanned + 1L]]$footnotes) {
          if (!(number %in% notes)) {
            notes <- c(notes, number)
            note_height <- note_height + footnote_heights[[number]]
          }
        }
        scanned <- scanned + 1L
      }
      used <- stop - start + note_height + as.integer(length(notes) > 0L)
      if (used > height) break
      chosen <- list(
          index = index,
          stop = stop,
          next_start = boundary$next_start,
          forced = boundary$forced,
          used = used,
          notes = sort(notes)
      )
      if (boundary$forced) break
    }
    content <- if (chosen$stop > start) lines[seq.int(start + 1L, chosen$stop)] else list()
    pages[[length(pages) + 1L]] <- record(
        content = content,
        footnotes = chosen$notes,
        height = chosen$used,
        ends_by_force = chosen$forced,
        blank = FALSE
    )
    start <- chosen$next_start
    first_boundary <- chosen$index + 1L
  }
  pages
}
