for (name in c(
    "document_parser",
    "hyphenation",
    "line_breaker",
    "page_builder",
    "renderer"
)) source(paste0(name, ".R"))

text_line <- function(text) record(text = text, footnotes = integer(), indexes = integer())
words_in <- function(text) {
  words <- split_all(text, " ")
  words[nzchar(words)]
}
split_label <- function(text) {
  positions <- gregexpr(" {#", text, fixed = TRUE)[[1L]]
  position <- tail(positions, 1L)
  if (endsWith(text, "}") && position != -1L) list(
      text = substr(text, 1L, position - 1L),
      label = substr(text, position + 3L, nchar(text) - 1L)
  ) else list(text = text, label = NULL)
}
new_metrics <- function(words, first_capacity, later_capacity, dictionary) {
  offsets <- integer()
  breaks <- list(list(start = c(1L, 0L), stop = c(1L, 0L), midword = FALSE, append = FALSE))
  offset <- 0L
  for (index in seq_along(words)) {
    word <- words[[index]]
    offsets <- c(offsets, offset)
    offset <- offset + nchar(word) + 1L
    for (point in split_points(dictionary, word)) {
      position <- c(index, point$position)
      breaks[[length(breaks) + 1L]] <- list(
          start = position,
          stop = position,
          midword = TRUE,
          append = point$append
      )
    }
    breaks[[length(breaks) + 1L]] <- list(
        start = c(index + 1L, 0L),
        stop = c(index, nchar(word)),
        midword = FALSE,
        append = FALSE
    )
  }
  list(
      words = words,
      first_capacity = first_capacity,
      later_capacity = later_capacity,
      offsets = offsets,
      breaks = breaks,
      count = length(breaks) - 1L
  )
}
metrics_capacity <- function(
    metrics,
    start
) if (start == 0L) metrics$first_capacity else metrics$later_capacity
metrics_length <- function(metrics, start, stop) {
  first <- metrics$breaks[[start + 1L]]$start
  last <- metrics$breaks[[stop + 1L]]$stop
  metrics$offsets[[last[[1L]]]] + last[[2L]] - metrics$offsets[[first[[1L]]]] - first[[2L]] + as.integer(metrics$breaks[[stop + 1L]]$append)
}
metrics_slack <- function(metrics, start, stop) metrics_capacity(metrics, start) - metrics_length(
    metrics,
    start,
    stop
)
measure <- function(metrics, start, stop) {
  first <- metrics$breaks[[start + 1L]]$start
  last <- metrics$breaks[[stop + 1L]]$stop
  pieces <- character()
  ranges <- list()
  for (word in seq.int(first[[1L]], last[[1L]])) {
    begin <- if (word == first[[1L]]) first[[2L]] else 0L
    end <- if (word == last[[1L]]) last[[2L]] else nchar(metrics$words[[word]])
    pieces <- c(pieces, substr(metrics$words[[word]], begin + 1L, end))
    ranges[[length(ranges) + 1L]] <- c(word, begin, end)
  }
  if (metrics$breaks[[stop + 1L]]$append) pieces[[length(pieces)]] <- paste0(tail(pieces, 1L), "-")
  list(
      pieces = pieces,
      ranges = ranges,
      slack = metrics_slack(metrics, start, stop),
      last = stop == metrics$count,
      midword = metrics$breaks[[stop + 1L]]$midword
  )
}
new_typesetter <- function(document, params, dictionary) {
  record(document = document, params = params, dictionary = dictionary, blocks = document$blocks, warnings = document$warnings,
         labels = list(), bibliography = list(), cited_entries = list(), body_blocks = list(), headings = list(), numbered_tables = list(),
         footnotes = character(), index_marks = character(), index_entries = list())
}
warn <- function(setter, line, message) setter$warnings[[length(setter$warnings) + 1L]] <- list(line, message)
register_document <- function(setter) {
  chapter <- section <- table_number <- 0L
  previous <- NULL
  for (index in seq_along(setter$blocks)) {
    block <- setter$blocks[[index]]
    block$id <- index
    block$label <- NULL
    kind <- block$kind
    if (kind %in% c("h1", "h2")) {
      label <- split_label(block$argument)
      block$text <- label$text
      block$label <- label$label
      if (kind == "h1") {
        chapter <- chapter + 1L
        section <- 0L
        block$number <- as.character(chapter)
        if (index != 1L) block$page_break <- TRUE
      } else {
        section <- section + 1L
        block$number <- paste0(chapter, ".", section)
      }
      setter$headings[[length(setter$headings) + 1L]] <- block
    } else if (kind == "enum") block$number <- if (!is.null(previous) && previous$kind == "enum") previous$number + 1L else 1L else if (kind == "table") {
      label <- split_label(block$caption)
      block$caption <- label$text
      block$label <- label$label
      block$number <- NULL
      if (nzchar(block$caption)) {
        table_number <- table_number + 1L
        block$number <- as.character(table_number)
        setter$numbered_tables[[length(setter$numbered_tables) + 1L]] <- block
      }
    }
    if (!is.null(block$label)) {
      label <- block$label
      if (!is.null(setter$labels[[label]])) {
        warn(setter, block$line_number, paste("duplicate label", label))
        block$label <- NULL
      } else setter$labels[[label]] <- block
    }
    if (kind == "paragraph" && !is.null(previous) && previous$kind %in% c("h1", "h2")) block$indent <- 0L
    if (kind %in% BODY_KINDS) {
      setter$body_blocks[[length(setter$body_blocks) + 1L]] <- block
      block$paragraph_number <- length(setter$body_blocks)
    }
    previous <- block
  }
  for (original in setter$document$bibliography) {
    key <- original$key
    if (!is.null(setter$bibliography[[key]])) warn(
        setter,
        original$line_number,
        paste("duplicate bibliography key", key)
    ) else {
      original$cited <- FALSE
      setter$bibliography[[key]] <- original
    }
  }
}
check_table <- function(setter, block) {
  count <- nchar(block$columns)
  rows <- list()
  for (line in block$inner_lines) {
    cells <- trimws(split_all(line[[2L]], "|"), whitespace = " ")
    if (length(cells) != count) {
      warn(setter, line[[1L]], paste("table row has", length(cells), "cells, expected", count))
      cells <- c(cells, rep.int("", max(0L, count - length(cells))))[seq_len(count)]
    }
    rows[[length(rows) + 1L]] <- cells
  }
  block$table_lines <- format_table(rows, block$columns, block$caption, block$number)
  excess <- max(nchar(block$table_lines)) - block$width
  if (excess > 0L) warn(setter, block$line_number, paste("table too wide by", excess))
}
accept_command <- function(setter, name, argument, line_number) {
  if (name %in% c("ref", "page")) {
    if (is.null(setter$labels[[argument]])) warn(setter, line_number, paste("undefined label", argument))
  } else if (name == "cite") {
    for (key in split_all(argument, ",")) {
      if (!is.null(setter$bibliography[[key]])) setter$bibliography[[key]]$cited <- TRUE else warn(
          setter,
          line_number,
          paste("undefined citation", key)
      )
    }
  } else if (name == "fn") {
    setter$footnotes <- c(setter$footnotes, argument)
    return(list(name = name, argument = length(setter$footnotes)))
  } else if (name == "idx") {
    setter$index_marks <- c(setter$index_marks, argument)
    return(list(name = name, argument = length(setter$index_marks)))
  }
  list(name = name, argument = argument)
}
parse_body_line <- function(setter, text, line_number) {
  tokens <- list()
  position <- 1L
  while (position <= nchar(text)) {
    relative <- regexpr("{", substring(text, position), fixed = TRUE)[[1L]]
    if (relative == -1L) {
      tokens[[length(tokens) + 1L]] <- substring(text, position)
      break
    }
    opening <- position + relative - 1L
    if (opening > position) tokens[[length(tokens) + 1L]] <- substr(text, position, opening - 1L)
    relative <- regexpr("}", substring(text, opening + 1L), fixed = TRUE)[[1L]]
    if (relative == -1L) {
      warn(setter, line_number, "unclosed brace")
      tokens[[length(tokens) + 1L]] <- substring(text, opening)
      break
    }
    closing <- opening + relative
    content <- substr(text, opening + 1L, closing - 1L)
    command <- partition_text(content, ":")
    if (command$left %in% c("ref", "page", "fn", "idx", "cite") && command$found && nzchar(command$right)) {
      tokens[[length(tokens) + 1L]] <- accept_command(setter, command$left, command$right, line_number)
    } else warn(setter, line_number, paste0("bad command {", content, "}"))
    position <- closing + 1L
  }
  tokens
}
check_document <- function(setter) {
  for (block in setter$blocks) {
    kind <- block$kind
    if (kind == "table") check_table(setter, block) else if (kind == "verbatim") {
      for (line in block$inner_lines) {
        excess <- nchar(line[[2L]]) - block$width
        if (excess > 0L) warn(setter, line[[1L]], paste("verbatim line too long by", excess))
      }
    } else if (kind %in% BODY_KINDS) {
      tokens <- list()
      for (index in seq_along(block$body_lines)) {
        line <- block$body_lines[[index]]
        if (index > 1L) tokens[[length(tokens) + 1L]] <- " "
        tokens <- c(tokens, parse_body_line(setter, line[[2L]], line[[1L]]))
      }
      block$tokens <- tokens
    }
  }
  for (entry in setter$bibliography) if (!entry$cited) warn(
      setter,
      entry$line_number,
      paste("unused bibliography entry", entry$key)
  )
}
assign_bibliography_labels <- function(setter) {
  for (entry in setter$bibliography) {
    if (!entry$cited) next
    surnames <- split_all(entry$author, " and ")
    base <- if (length(surnames) == 1L) substr(surnames[[1L]], 1L, 3L) else if (length(surnames) <= 4L) paste(substr(surnames, 1L, 1L), collapse = "") else paste0(
        paste(substr(surnames[1L:3L], 1L, 1L), collapse = ""),
        "+"
    )
    entry$base_label <- paste0(base, substr(entry$year, 3L, 4L))
    setter$cited_entries[[length(setter$cited_entries) + 1L]] <- entry
  }
  if (!length(setter$cited_entries)) return(invisible(NULL))
  entries <- setter$cited_entries
  positions <- order(vapply(entries, function(entry) entry$base_label, ""), vapply(entries, function(entry) entry$author, ""),
                     vapply(
                         entries,
                         function(entry) entry$title,
                         ""
                     ), vapply(entries, function(entry) entry$key, ""), method = "radix")
  setter$cited_entries <- entries[positions]
  for (entry in setter$cited_entries) {
    group <- Filter(function(other) other$base_label == entry$base_label, setter$cited_entries)
    index <- which(vapply(group, function(other) identical(other, entry), FALSE))[[1L]]
    entry$label <- paste0(entry$base_label, if (length(group) > 1L) letters[[index]] else "")
  }
}
new_index_entry <- function(name) record(
    name = name,
    marks = integer(),
    references = character(),
    children = list()
)
prepare_index <- function(setter) {
  for (number in seq_along(setter$index_marks)) {
    phrase <- partition_text(setter$index_marks[[number]], "|")
    part <- partition_text(phrase$left, "!")
    if (is.null(setter$index_entries[[part$left]])) setter$index_entries[[part$left]] <- new_index_entry(part$left)
    parent <- setter$index_entries[[part$left]]
    entry <- parent
    if (part$found) {
      if (is.null(parent$children[[part$right]])) parent$children[[part$right]] <- new_index_entry(part$right)
      entry <- parent$children[[part$right]]
    }
    if (phrase$found) entry$references <- union(
        entry$references,
        phrase$right
    ) else entry$marks <- c(entry$marks, number)
  }
}
citation_text <- function(setter, argument) {
  labels <- character()
  undefined <- FALSE
  for (key in split_all(argument, ",")) {
    entry <- setter$bibliography[[key]]
    if (is.null(entry)) undefined <- TRUE else labels <- union(labels, entry$label)
  }
  parts <- sort(labels, method = "radix")
  if (undefined) parts <- c(parts, "?")
  paste0("[", paste(parts, collapse = ", "), "]")
}
expand_body <- function(setter, block, page_values) {
  parts <- character()
  marks <- list()
  offset <- 0L
  for (token in block$tokens) {
    if (is.character(token)) text <- token else {
      name <- token$name
      argument <- token$argument
      if (name == "idx") {
        marks[[length(marks) + 1L]] <- list(offset = offset - 1L, kind = name, number = argument)
        next
      }
      if (name == "fn") {
        marks[[length(marks) + 1L]] <- list(offset = offset, kind = name, number = argument)
        text <- paste0("[", argument, "]")
      } else if (name == "ref") text <- if (is.null(setter$labels[[argument]])) "??" else setter$labels[[argument]]$number else if (name == "page") text <- if (is.null(page_values[[argument]])) "??" else page_values[[argument]] else text <- citation_text(
          setter,
          argument
      )
    }
    parts <- c(parts, text)
    offset <- offset + nchar(text)
  }
  expanded <- paste(parts, collapse = "")
  matches <- gregexpr("[^ ]+", expanded)[[1L]]
  starts <- as.integer(matches) - 1L
  words <- regmatches(expanded, list(matches))[[1L]]
  word_marks <- vector("list", length(words))
  for (mark in marks) {
    word <- findInterval(mark$offset, starts)
    word_marks[[word]][[length(word_marks[[word]]) + 1L]] <- list(
        kind = mark$kind,
        number = mark$number,
        position = mark$offset - starts[[word]]
    )
  }
  list(words = words, marks = word_marks)
}
lay_out_text <- function(setter, words, capacities, alignment, prefixes, method, word_marks = list()) {
  metrics <- new_metrics(words, capacities[[1L]], capacities[[2L]], setter$dictionary)
  breaking <- break_text(metrics, method, setter$params)
  lines <- broken <- list()
  start <- 0L
  for (index in seq_along(breaking$breaking)) {
    stop <- breaking$breaking[[index]]
    measured <- measure(metrics, start, stop)
    text <- display_line(measured$pieces, measured$slack, alignment, measured$last)
    line <- text_line(paste0(prefixes[[if (index == 1L) 1L else 2L]], text))
    for (range in measured$ranges) {
      word <- range[[1L]]
      if (word > length(word_marks)) next
      for (mark in word_marks[[word]]) {
        if (range[[2L]] <= mark$position && mark$position < range[[3L]]) {
          if (mark$kind == "fn") line$footnotes <- c(
              line$footnotes,
              mark$number
          ) else line$indexes <- c(line$indexes, mark$number)
        }
      }
    }
    lines[[length(lines) + 1L]] <- line
    broken[[length(broken) + 1L]] <- measured
    start <- stop
  }
  record(lines = lines, broken = broken, cost = breaking$cost)
}
body_format <- function(block) {
  width <- block$width
  kind <- block$kind
  if (kind == "paragraph") return(list(
      capacities = c(width - block$indent, width),
      prefixes = c(strrep(" ", block$indent), "")
  ))
  if (kind == "item") return(list(capacities = rep.int(width - 2L, 2L), prefixes = c("- ", "  ")))
  if (kind == "enum") return(list(
      capacities = rep.int(width - 4L, 2L),
      prefixes = c(sprintf("%2d. ", block$number), strrep(" ", 4L))
  ))
  if (kind == "quote") return(list(
      capacities = rep.int(width - 8L, 2L),
      prefixes = rep.int(strrep(" ", 4L), 2L)
  ))
  first <- if (nchar(block$term) <= 10L) paste0(
      block$term,
      strrep(" ", 12L - nchar(block$term))
  ) else strrep(" ", 12L)
  list(capacities = rep.int(width - 12L, 2L), prefixes = c(first, strrep(" ", 12L)))
}
lay_out_body <- function(setter, block, page_values, method) {
  expanded <- expand_body(setter, block, page_values)
  format <- body_format(block)
  result <- lay_out_text(
      setter,
      expanded$words,
      format$capacities,
      block$align,
      format$prefixes,
      method,
      expanded$marks
  )
  if (block$kind == "term" && nchar(block$term) >= 11L) result$lines <- c(
      list(text_line(block$term)),
      result$lines
  )
  result
}
lay_out_footnotes <- function(setter, method) {
  lapply(seq_along(setter$footnotes), function(number) {
    prefix <- paste0("[", number, "] ")
    capacity <- setter$document$page_width - nchar(prefix)
    lay_out_text(
        setter,
        words_in(setter$footnotes[[number]]),
        c(capacity, capacity),
        "left",
        c(prefix, strrep(" ", nchar(prefix))),
        method
    )
  })
}
lay_out_reference <- function(setter, entry, width, method) {
  margin <- max(vapply(setter$cited_entries, function(item) nchar(item$label), 0L)) + 3L
  text <- paste0(entry$author, ". ", entry$year, ". ", entry$title)
  label <- paste0("[", entry$label, "]")
  prefix <- paste0(label, strrep(" ", max(0L, margin - nchar(label))))
  lay_out_text(
      setter,
      words_in(text),
      rep.int(width - margin, 2L),
      "left",
      c(prefix, strrep(" ", margin)),
      method
  )
}
page_list <- function(numbers) {
  numbers <- sort(unique(numbers))
  parts <- character()
  index <- 1L
  while (index <= length(numbers)) {
    last <- index
    while (last < length(numbers) && numbers[[last + 1L]] == numbers[[last]] + 1L) last <- last + 1L
    if (last - index >= 2L) parts <- c(
        parts,
        paste0(numbers[[index]], "-", numbers[[last]])
    ) else parts <- c(parts, as.character(numbers[seq.int(index, last)]))
    index <- last + 1L
  }
  paste(parts, collapse = ", ")
}
index_entry_line <- function(entry, mark_pages, child = FALSE) {
  text <- paste0(if (child) "  " else "", entry$name)
  numbers <- unlist(
      lapply(entry$marks, function(number) mark_pages[[as.character(number)]]),
      use.names = FALSE
  )
  if (length(numbers)) text <- paste0(text, ", ", page_list(numbers))
  if (length(entry$references)) text <- paste0(
      text,
      ", see ",
      paste(sort(entry$references, method = "radix"), collapse = ", ")
  )
  text
}
sorted_names <- function(items) {
  if (!length(items)) return(character())
  names <- names(items)
  names[order(tolower(names), names, method = "radix")]
}
index_lines <- function(setter, mark_pages) {
  lines <- character()
  previous <- NULL
  for (name in sorted_names(setter$index_entries)) {
    parent <- setter$index_entries[[name]]
    group <- if (is_letter(substr(name, 1L, 1L))) toupper(substr(name, 1L, 1L)) else "Symbols"
    if (!identical(group, previous)) {
      lines <- c(lines, group)
      previous <- group
    }
    lines <- c(lines, index_entry_line(parent, mark_pages))
    for (child in sorted_names(parent$children)) lines <- c(
        lines,
        index_entry_line(parent$children[[child]], mark_pages, TRUE)
    )
  }
  lines
}
contents_lines <- function(setter, block, block_pages) {
  entries <- if (block$kind == "toc") setter$headings else setter$numbered_tables
  vapply(entries, function(entry) {
    left <- if (block$kind == "toc") paste0(
        if (entry$kind == "h2") "  " else "",
        entry$number,
        " ",
        entry$text
    ) else paste0("Table ", entry$number, ". ", entry$caption)
    page <- block_pages[[as.character(entry$id)]]
    number <- if (is.null(page)) "??" else page$display
    paste0(left, " ", strrep(".", block$width - nchar(left) - nchar(number) - 2L), " ", number)
  }, "")
}
add_layout_block <- function(layout, source, kind, lines, list_mark = FALSE, first = TRUE) {
  if (first) {
    lines[[1L]]$anchor <- source$id
    if (source$kind == "h1") lines[[1L]]$chapter_start <- TRUE
  }
  c(
      layout,
      list(record(kind = kind, lines = lines, list = list_mark, page_break = first && source$page_break))
  )
}
build_layout_blocks <- function(setter, page_values, method, result) {
  layout <- list()
  for (block in setter$blocks) {
    kind <- block$kind
    if (kind %in% BODY_KINDS) {
      body <- lay_out_body(setter, block, page_values, method)
      result$bodies[[as.character(block$id)]] <- body
      result$warning_texts[[length(result$warning_texts) + 1L]] <- list(
          paste("paragraph", block$paragraph_number),
          body,
          block$align == "justify"
      )
      layout <- add_layout_block(layout, block, "flow", body$lines, kind %in% c("item", "enum", "term"))
    } else if (kind %in% c("title", "author")) {
      text <- if (kind == "title") toupper(block$argument) else block$argument
      text <- paste0(strrep(" ", (block$width - nchar(text)) %/% 2L), text)
      layout <- add_layout_block(layout, block, "heading", list(text_line(text)))
    } else if (kind %in% c("h1", "h2")) {
      text <- if (kind == "h1") toupper(block$text) else block$text
      text <- paste(block$number, text)
      rule <- strrep(if (kind == "h1") "=" else "-", nchar(text))
      layout <- add_layout_block(layout, block, "heading", lapply(c(text, rule), text_line))
    } else if (kind == "table") layout <- add_layout_block(layout, block, "solid", lapply(block$table_lines, text_line)) else if (kind == "verbatim") layout <- add_layout_block(
        layout,
        block,
        "flow",
        lapply(block$inner_lines, function(line) text_line(line[[2L]]))
    ) else if (kind %in% c("toc", "lot", "index")) {
      title <- switch(kind, toc = "CONTENTS", lot = "TABLES", index = "INDEX")
      layout <- add_layout_block(
          layout,
          block,
          "heading",
          lapply(c(title, strrep("=", nchar(title))), text_line)
      )
      entries <- if (kind == "index") index_lines(setter, list()) else contents_lines(setter, block, list())
      lines <- lapply(entries, text_line)
      layout <- add_layout_block(layout, block, "flow", lines, first = FALSE)
      result$generated[[length(result$generated) + 1L]] <- list(block, lines)
    } else if (kind == "bibliography") {
      layout <- add_layout_block(layout, block, "heading", lapply(c("REFERENCES", "=========="), text_line))
      for (entry in setter$cited_entries) {
        reference <- lay_out_reference(setter, entry, block$width, method)
        result$warning_texts[[length(result$warning_texts) + 1L]] <- list(
            paste("reference", entry$label),
            reference,
            FALSE
        )
        layout <- add_layout_block(layout, block, "flow", reference$lines, list_mark = TRUE, first = FALSE)
      }
    }
  }
  layout
}
roman <- function(number) paste0(
    strrep("x", number %/% 10L),
    c("", "i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix")[[number %% 10L + 1L]]
)
number_pages <- function(setter, pages, result) {
  numbered <- list()
  for (page in pages) {
    chapter_start <- isTRUE(page$content[[1L]]$chapter_start)
    serial <- length(numbered) + 1L
    if (chapter_start && serial %% 2L == 0L) {
      numbered[[length(numbered) + 1L]] <- record(
          serial = serial,
          blank = TRUE,
          content = list(),
          footnotes = integer(),
          height = 0L,
          ends_by_force = TRUE,
          chapter_start = FALSE
      )
      serial <- serial + 1L
    }
    page$serial <- serial
    page$chapter_start <- chapter_start
    numbered[[length(numbered) + 1L]] <- page
  }
  block_pages <- list()
  for (page in numbered) for (line in page$content) if (!is.null(line$anchor)) block_pages[[as.character(line$anchor)]] <- page
  front_matter <- if (length(setter$headings)) block_pages[[as.character(setter$headings[[1L]]$id)]]$serial - 1L else 0L
  mark_pages <- list()
  for (page in numbered) {
    serial <- page$serial
    page$body_number <- serial - front_matter
    page$display <- if (serial <= front_matter) roman(serial) else as.character(page$body_number)
    for (line in page$content) for (mark in line$indexes) mark_pages[[as.character(mark)]] <- page$body_number
  }
  result$pages <- numbered
  result$front_matter <- front_matter
  result$block_pages <- block_pages
  result$mark_pages <- mark_pages
  result$label_values <- lapply(setter$labels, function(block) block_pages[[as.character(block$id)]]$display)
}
layout_once <- function(setter, page_values, method) {
  footnotes <- lay_out_footnotes(setter, method)
  result <- record(
      method = method,
      bodies = list(),
      footnotes = footnotes,
      warning_texts = list(),
      generated = list()
  )
  blocks <- build_layout_blocks(setter, page_values, method, result)
  heights <- vapply(footnotes, function(note) length(note$lines), 0L)
  pages <- choose_pages(
      blocks,
      heights,
      setter$document$height,
      setter$params$orphan_lines,
      setter$params$widow_lines
  )
  number_pages(setter, pages, result)
  for (number in seq_along(footnotes)) result$warning_texts[[length(result$warning_texts) + 1L]] <- list(
      paste("footnote", number),
      footnotes[[number]],
      FALSE
  )
  result
}
complete_generated_lines <- function(setter, result) {
  for (generated in result$generated) {
    block <- generated[[1L]]
    records <- generated[[2L]]
    texts <- if (block$kind == "index") index_lines(setter, result$mark_pages) else contents_lines(
        setter,
        block,
        result$block_pages
    )
    for (i in seq_along(records)) records[[i]]$text <- texts[[i]]
  }
}
assemble_pages <- function(setter, result) {
  chapter <- section <- ""
  height <- setter$document$height
  total <- length(result$pages) - result$front_matter
  for (page in result$pages) {
    if (page$blank) {
      page$header <- page$footer <- ""
      page$body <- rep.int("", height)
      next
    }
    for (line in page$content) {
      if (is.null(line$anchor)) next
      block <- setter$blocks[[line$anchor]]
      if (block$kind == "h1") {
        chapter <- paste(block$number, block$text)
        section <- ""
      } else if (block$kind == "h2") section <- paste(block$number, block$text)
    }
    values <- list(page = page$display, pages = as.character(total), chapter = chapter, section = section)
    page$header <- if (page$chapter_start) "" else running_head(
        setter$document$header,
        values,
        setter$document$page_width,
        page$serial
    )
    page$footer <- running_head(setter$document$footer, values, setter$document$page_width, page$serial)
    content <- vapply(page$content, function(line) line$text, "")
    note_lines <- character()
    for (number in page$footnotes) note_lines <- c(
        note_lines,
        vapply(result$footnotes[[number]]$lines, function(line) line$text, "")
    )
    page$body <- if (length(note_lines)) c(
        content,
        rep.int("", height - length(content) - length(note_lines) - 1L),
        "----------",
        note_lines
    ) else c(content, rep.int("", height - length(content)))
  }
}
layout <- function(setter, method) {
  page_values <- lapply(setter$labels, function(block) "??")
  repeat {
    result <- layout_once(setter, page_values, method)
    if (identical(result$label_values, page_values)) break
    page_values <- result$label_values
  }
  complete_generated_lines(setter, result)
  assemble_pages(setter, result)
  result
}
layout_warnings <- function(setter, result) {
  warnings <- character()
  for (entry in result$warning_texts) {
    name <- entry[[1L]]
    text <- entry[[2L]]
    justify <- entry[[3L]]
    for (number in seq_along(text$broken)) {
      line <- text$broken[[number]]
      slack <- line$slack
      if (slack < 0L) warnings <- c(warnings, paste0(name, " line ", number, ": overfull by ", -slack)) else if (justify && !line$last && slack >= setter$params$underfull_slack) warnings <- c(
          warnings,
          paste0(name, " line ", number, ": underfull, slack ", slack)
      )
    }
  }
  for (page in result$pages) {
    if (page$blank || page$ends_by_force) next
    empty <- setter$document$height - page$height
    if (empty >= setter$params$underfull_page) warnings <- c(
        warnings,
        paste0("page ", page$serial, ": underfull, ", empty, " empty lines")
    )
  }
  hyphenated <- sum(vapply(result$bodies, function(body) sum(vapply(body$broken, `[[`, FALSE, "midword")), 0L))
  warnings <- c(warnings, paste0(length(result$pages), " pages, ", hyphenated, " hyphenated lines"))
  paste0(result$method, ": ", warnings)
}
statistics <- function(setter, optimal, greedy_result) {
  lines <- "paragraph,lines_kp,cost_kp,lines_greedy,cost_greedy"
  totals <- integer(4L)
  for (block in setter$body_blocks) {
    kp <- optimal$bodies[[as.character(block$id)]]
    greedy_body <- greedy_result$bodies[[as.character(block$id)]]
    values <- c(length(kp$broken), kp$cost, length(greedy_body$broken), greedy_body$cost)
    totals <- totals + values
    lines <- c(lines, paste(c(block$paragraph_number, values), collapse = ","))
  }
  c(lines, paste0("total,", paste(totals, collapse = ",")))
}
main <- function() {
  params <- list()
  for (line in readLines(file.path("input", "params.txt"), warn = FALSE)) {
    words <- split_all(line, " ")
    params[[words[[1L]]]] <- as.integer(words[[2L]])
  }
  document <- parse_document(readLines(file.path("input", "document.txt"), warn = FALSE))
  dictionary <- new_hyphenation(
      readLines(file.path("input", "hyphenation.txt"), warn = FALSE),
      document$hyphenation_words,
      params$left_min,
      params$right_min
  )
  setter <- new_typesetter(document, params, dictionary)
  register_document(setter)
  check_document(setter)
  assign_bibliography_labels(setter)
  prepare_index(setter)
  setter$warnings <- setter$warnings[order(vapply(setter$warnings, `[[`, 0L, 1L), seq_along(setter$warnings), method = "radix")]
  optimal <- layout(setter, "kp")
  greedy_result <- layout(setter, "greedy")
  warnings <- vapply(
      setter$warnings,
      function(warning) paste0("line ", warning[[1L]], ": ", warning[[2L]]),
      ""
  )
  warnings <- c(warnings, layout_warnings(setter, optimal), layout_warnings(setter, greedy_result))
  outputs <- list("pages.txt" = pages_lines(optimal$pages), "greedy_pages.txt" = pages_lines(greedy_result$pages),
                  "stats.csv" = statistics(setter, optimal, greedy_result), "log.txt" = warnings)
  dir.create("output", showWarnings = FALSE)
  for (name in names(outputs)) writeLines(outputs[[name]], file.path("output", name), useBytes = TRUE)
}
main()
