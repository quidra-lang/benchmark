whitespace <- " \n"
punctuation <- "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
toc_marker <- "\001toc\002"

char_at <- function(text, at) {
  if (at < 1L || at > nchar(text)) "" else substr(text, at, at)
}
has <- function(chars, char) nzchar(char) && grepl(char, chars, fixed = TRUE)
starts <- function(text, prefix, at = 1L) substr(text, at, at + nchar(prefix) - 1L) == prefix
slice <- function(text, first, end = nchar(text) + 1L) {
  if (end <= first) "" else substr(text, first, end - 1L)
}
trim_spaces <- function(text) gsub("\\A +| +\\z", "", text, perl = TRUE)
left_trim <- function(text) sub("\\A +", "", text, perl = TRUE)
right_trim <- function(text) sub(" +\\z", "", text, perl = TRUE)
match_parts <- function(pattern, text) {
  found <- regmatches(text, regexec(pattern, text, perl = TRUE))[[1L]]
  if (length(found)) found else NULL
}
whole <- function(pattern, text) grepl(paste0("\\A(?:", pattern, ")\\z"), text, perl = TRUE)
escape_html <- function(text) {
  for (pair in list(c("&", "&amp;"), c("<", "&lt;"), c(">", "&gt;"), c('"', "&quot;"))) {
    text <- gsub(pair[1L], pair[2L], text, fixed = TRUE)
  }
  text
}
strip_tags <- function(text) gsub("<[^>]*>", "", text, perl = TRUE)
normalize_label <- function(text) trim_spaces(gsub("[ \n]+", " ", tolower(text)))
lookup <- function(map, key) if (nzchar(key)) map[[key]] else NULL
skip_space <- function(text, at) {
  while (at <= nchar(text) && has(whitespace, char_at(text, at))) at <- at + 1L
  at
}
escaped_read <- function(text, at, stops) {
  result <- character()
  while (at <= nchar(text) && !has(stops, char_at(text, at))) {
    if (char_at(text, at) == "\\" && has(punctuation, char_at(text, at + 1L))) at <- at + 1L
    result <- c(result, char_at(text, at))
    at <- at + 1L
  }
  list(paste0(result, collapse = ""), at)
}
opening_fence <- function(line) {
  found <- match_parts("\\A(`{3,}|~{3,})", line)
  if (is.null(found)) return(NULL)
  fence <- found[1L]
  info <- trim_spaces(slice(line, nchar(fence) + 1L))
  if (char_at(fence, 1L) == "`" && grepl("`", info, fixed = TRUE)) return(NULL)
  list(fence, info)
}
atx_heading <- function(line) {
  found <- match_parts("\\A(#{1,6})(?: |\\z)", line)
  if (is.null(found)) return(NULL)
  level <- nchar(found[2L])
  text <- trim_spaces(slice(line, level + 1L))
  trimmed <- sub("#+\\z", "", text, perl = TRUE)
  if (!nzchar(trimmed) || endsWith(trimmed, " ")) text <- trim_spaces(trimmed)
  list(kind = "heading", text = text, number = level)
}
is_rule <- function(line) whole("-{3,}|\\*{3,}|_{3,}", gsub(" ", "", line, fixed = TRUE))
list_marker <- function(line) {
  if (is_rule(line)) return(NULL)
  found <- match_parts("\\A(?:([-*+])|([0-9]{1,9})([.)])) +", line)
  if (is.null(found)) return(NULL)
  ordered <- nzchar(found[3L])
  list(kind = if (ordered) found[4L] else found[2L], ordered = ordered,
       number = if (ordered) as.integer(found[3L]) else 1L,
       content = slice(line, nchar(found[1L]) + 1L))
}
interrupts_paragraph <- function(line) {
  !startsWith(line, " ") && (!is.null(opening_fence(line)) || !is.null(atx_heading(line)) ||
    is_rule(line) || startsWith(line, ">") || !is.null(list_marker(line)))
}
split_cells <- function(line) {
  text <- trim_spaces(line)
  at <- if (startsWith(text, "|")) 2L else 1L
  cells <- ""
  separator <- FALSE
  while (at <= nchar(text)) {
    char <- char_at(text, at)
    at <- at + 1L
    separator <- FALSE
    last <- length(cells)
    if (char == "\\" && at <= nchar(text)) {
      if (char_at(text, at) != "|") cells[last] <- paste0(cells[last], "\\")
      cells[last] <- paste0(cells[last], char_at(text, at))
      at <- at + 1L
    } else if (char == "|") {
      cells <- c(cells, "")
      separator <- TRUE
    } else cells[last] <- paste0(cells[last], char)
  }
  if (separator) cells <- head(cells, -1L)
  vapply(cells, trim_spaces, character(1L), USE.NAMES = FALSE)
}

new_block_parser <- function() {
  state <- new.env(parent = emptyenv())
  state$references <- list()
  state$footnotes <- list()

  definition <- function(line) {
    found <- match_parts("\\A\\[\\^([A-Za-z0-9_-]+)\\]:(.*)\\z", line)
    if (!is.null(found) && nzchar(trim_spaces(found[3L]))) {
      name <- tolower(found[2L])
      if (is.null(state$footnotes[[name]])) state$footnotes[[name]] <- trim_spaces(found[3L])
      return(TRUE)
    }
    if (!startsWith(line, "[")) return(FALSE)
    close <- regexpr("]", line, fixed = TRUE)[1L]
    if (close < 1L || char_at(line, close + 1L) != ":") return(FALSE)
    label <- slice(line, 2L, close)
    if (grepl("[", label, fixed = TRUE) || !nzchar(trim_spaces(label)) || startsWith(label, "^")) return(FALSE)
    read <- escaped_read(line, skip_space(line, close + 2L), " ")
    url <- read[[1L]]
    end <- read[[2L]]
    if (!nzchar(url)) return(FALSE)
    at <- skip_space(line, end)
    title <- NULL
    if (at <= nchar(line)) {
      if (at == end || !has("\"'", char_at(line, at))) return(FALSE)
      read <- escaped_read(line, at + 1L, char_at(line, at))
      if (read[[2L]] != nchar(line)) return(FALSE)
      title <- read[[1L]]
    }
    name <- normalize_label(label)
    if (is.null(state$references[[name]])) state$references[[name]] <- list(url = url, title = title)
    TRUE
  }

  parse <- function(lines) {
    blocks <- list()
    at <- 1L
    while (at <= length(lines)) {
      line <- lines[at]
      if (!nzchar(line)) {
        at <- at + 1L
        next
      }
      if (startsWith(line, "    ")) {
        end <- at
        while (end <= length(lines) && (!nzchar(lines[end]) || startsWith(lines[end], "    "))) end <- end + 1L
        while (!nzchar(lines[end - 1L])) end <- end - 1L
        code <- vapply(lines[seq.int(at, end - 1L)], function(row) slice(row, 5L), character(1L))
        blocks[[length(blocks) + 1L]] <- list(kind = "code", text = "", lines = code)
        at <- end
        next
      }
      if (!startsWith(line, " ")) {
        fence <- opening_fence(line)
        if (!is.null(fence)) {
          code <- character()
          at <- at + 1L
          while (at <= length(lines)) {
            row <- lines[at]
            at <- at + 1L
            if (nchar(row) >= nchar(fence[[1L]]) && !nzchar(gsub(char_at(fence[[1L]], 1L), "", row, fixed = TRUE))) break
            code <- c(code, row)
          }
          language <- sub(" .*\\z", "", fence[[2L]], perl = TRUE)
          blocks[[length(blocks) + 1L]] <- list(kind = "code", text = language, lines = code)
          next
        }
        heading <- atx_heading(line)
        if (!is.null(heading)) {
          blocks[[length(blocks) + 1L]] <- heading
          at <- at + 1L
          next
        }
        if (is_rule(line)) {
          blocks[[length(blocks) + 1L]] <- list(kind = "rule")
          at <- at + 1L
          next
        }
        if (startsWith(line, ">")) {
          content <- character()
          while (at <= length(lines) && startsWith(lines[at], ">")) {
            row <- slice(lines[at], 2L)
            if (startsWith(row, " ")) row <- slice(row, 2L)
            content <- c(content, row)
            at <- at + 1L
          }
          alert <- match_parts("\\A\\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\\]\\z", content[1L])
          if (!is.null(alert)) content <- content[-1L]
          blocks[[length(blocks) + 1L]] <- list(kind = if (is.null(alert)) "quote" else "alert",
            text = if (is.null(alert)) "" else alert[2L], children = parse(content))
          next
        }
        marker <- list_marker(line)
        if (!is.null(marker)) {
          kind <- marker$kind
          ordered <- marker$ordered
          number <- marker$number
          items <- list()
          repeat {
            content <- marker$content
            at <- at + 1L
            while (at <= length(lines) && startsWith(lines[at], "  ")) {
              content <- c(content, slice(lines[at], 3L))
              at <- at + 1L
            }
            items[[length(items) + 1L]] <- parse(content)
            following <- at
            while (following <= length(lines) && !nzchar(lines[following])) following <- following + 1L
            marker <- if (following <= length(lines)) list_marker(lines[following]) else NULL
            if (is.null(marker) || marker$kind != kind || marker$ordered != ordered) break
            at <- following
          }
          blocks[[length(blocks) + 1L]] <- list(kind = "list", ordered = ordered, number = number, items = items)
          next
        }
        if (definition(line)) {
          at <- at + 1L
          next
        }
        if (at < length(lines) && grepl("|", line, fixed = TRUE) && grepl("|", lines[at + 1L], fixed = TRUE)) {
          header <- split_cells(line)
          delimiters <- split_cells(lines[at + 1L])
          if (length(header) == length(delimiters) && all(vapply(delimiters, function(cell) whole(":?-+:?", cell), logical(1L)))) {
            alignments <- vapply(delimiters, function(cell) {
              if (startsWith(cell, ":")) {
                if (endsWith(cell, ":")) "center" else "left"
              } else if (endsWith(cell, ":")) "right" else ""
            }, character(1L))
            rows <- list()
            at <- at + 2L
            while (at <= length(lines) && grepl("|", lines[at], fixed = TRUE)) {
              row <- head(split_cells(lines[at]), length(header))
              rows[[length(rows) + 1L]] <- c(row, rep("", length(header) - length(row)))
              at <- at + 1L
            }
            blocks[[length(blocks) + 1L]] <- list(kind = "table", alignments = alignments, lines = header, rows = rows)
            next
          }
        }
      }
      text <- left_trim(line)
      at <- at + 1L
      level <- NULL
      while (at <= length(lines) && nzchar(lines[at])) {
        if (whole("={3,}|-{3,}", lines[at])) {
          level <- if (char_at(lines[at], 1L) == "=") 1L else 2L
          at <- at + 1L
          break
        }
        if (interrupts_paragraph(lines[at])) break
        text <- c(text, left_trim(lines[at]))
        at <- at + 1L
      }
      text <- paste(text, collapse = "\n")
      blocks[[length(blocks) + 1L]] <- list(kind = if (!is.null(level)) "heading" else if (text == "[TOC]") "toc" else "paragraph",
        text = text, number = level)
    }
    blocks
  }
  list(parse = parse, state = state)
}

run_end <- function(text, at) {
  char <- char_at(text, at)
  at <- at + 1L
  while (at <= nchar(text) && char_at(text, at) == char) at <- at + 1L
  at
}
backtick_closer <- function(text, at, length) {
  while (at <= nchar(text)) {
    offset <- regexpr("`", slice(text, at), fixed = TRUE)[1L]
    if (offset < 1L) return(NULL)
    at <- at + offset - 1L
    end <- run_end(text, at)
    if (end - at == length) return(at)
    at <- end
  }
  NULL
}
closing_bracket <- function(text, at) {
  depth <- 0L
  while (at <= nchar(text)) {
    char <- char_at(text, at)
    if (char == "\\") {
      at <- at + 2L
      next
    }
    if (char == "`") {
      end <- run_end(text, at)
      close <- backtick_closer(text, end, end - at)
      at <- if (is.null(close)) end else close + end - at
      next
    }
    if (char == "[") depth <- depth + 1L
    if (char == "]") {
      depth <- depth - 1L
      if (depth == 0L) return(at)
    }
    at <- at + 1L
  }
  NULL
}
emphasis <- function(pieces, first = 1L, end = length(pieces) + 1L) {
  html <- character()
  at <- first
  while (at < end) {
    piece <- pieces[[at]]
    if (is.character(piece)) html <- c(html, piece) else {
      close <- end
      if (piece$can_open && at + 1L < end) {
        for (index in seq.int(at + 1L, end - 1L)) {
          other <- pieces[[index]]
          if (is.list(other) && other$char == piece$char && other$length == piece$length && other$can_close) {
            close <- index
            break
          }
        }
      }
      if (close == end) html <- c(html, strrep(piece$char, piece$length)) else {
        tags <- if (piece$char == "~") c("<del>", "</del>") else switch(as.character(piece$length),
          "1" = c("<em>", "</em>"), "2" = c("<strong>", "</strong>"), "3" = c("<em><strong>", "</strong></em>"))
        html <- c(html, tags[1L], emphasis(pieces, at + 1L, close), tags[2L])
        at <- close
      }
    }
    at <- at + 1L
  }
  paste0(html, collapse = "")
}

new_renderer <- function(references, footnotes) {
  state <- new.env(parent = emptyenv())
  state$used_ids <- list()
  state$headings <- list()
  state$note_numbers <- list()
  state$note_counts <- list()

  reference_id <- function(number, count) paste0("fnref-", number, if (count == 1L) "" else paste0("-", count))
  footnote_reference <- function(name) {
    if (is.null(state$note_numbers[[name]])) {
      state$note_numbers[[name]] <- length(state$note_numbers) + 1L
      state$note_counts[[name]] <- 0L
    }
    number <- state$note_numbers[[name]]
    state$note_counts[[name]] <- state$note_counts[[name]] + 1L
    paste0('<sup id="', reference_id(number, state$note_counts[[name]]), '"><a href="#fn-', number, '">', number, '</a></sup>')
  }

  destination <- function(text, at, label) {
    if (char_at(text, at) == "[") {
      offset <- regexpr("]", slice(text, at + 1L), fixed = TRUE)[1L]
      if (offset > 0L) {
        close <- at + offset
        name <- slice(text, at + 1L, close)
        if (!grepl("[", name, fixed = TRUE)) {
          reference <- lookup(references, normalize_label(if (nzchar(name)) name else label))
          return(if (is.null(reference)) NULL else list(reference, close + 1L))
        }
      }
    } else if (char_at(text, at) == "(") {
      read <- escaped_read(text, skip_space(text, at + 1L), " \n)")
      url <- read[[1L]]
      end <- read[[2L]]
      position <- skip_space(text, end)
      title <- NULL
      valid <- TRUE
      if (position > end && has("\"'", char_at(text, position))) {
        read <- escaped_read(text, position + 1L, char_at(text, position))
        title <- read[[1L]]
        valid <- read[[2L]] <= nchar(text)
        if (valid) position <- skip_space(text, read[[2L]] + 1L)
      }
      if (valid && char_at(text, position) == ")") return(list(list(url = url, title = title), position + 1L))
    }
    reference <- lookup(references, normalize_label(label))
    if (is.null(reference)) NULL else list(reference, at)
  }

  inline <- function(text, links = TRUE, notes = TRUE) {
    pieces <- list()
    at <- 1L
    while (at <= nchar(text)) {
      char <- char_at(text, at)
      following <- char_at(text, at + 1L)
      if (char == "\\") {
        if (has(punctuation, following)) {
          piece <- escape_html(following)
          at <- at + 2L
        } else if (following == "\n") {
          piece <- "<br />\n"
          at <- at + 2L
        } else {
          piece <- "\\"
          at <- at + 1L
        }
        pieces[[length(pieces) + 1L]] <- piece
        next
      }
      if (char == "`") {
        end <- run_end(text, at)
        close <- backtick_closer(text, end, end - at)
        if (is.null(close)) {
          piece <- slice(text, at, end)
          at <- end
        } else {
          code <- gsub("\n", " ", slice(text, end, close), fixed = TRUE)
          if (startsWith(code, " ") && endsWith(code, " ") && nzchar(trim_spaces(code))) code <- slice(code, 2L, nchar(code))
          piece <- paste0("<code>", escape_html(code), "</code>")
          at <- close + end - at
        }
        pieces[[length(pieces) + 1L]] <- piece
        next
      }
      if (links && char == "<") {
        offset <- regexpr(">", slice(text, at + 1L), fixed = TRUE)[1L]
        if (offset > 0L) {
          close <- at + offset
          target <- slice(text, at + 1L, close)
          href <- NULL
          if (!grepl("[ \n<]", target) && grepl("\\Ahttps?://.+", target, perl = TRUE)) href <- target else
            if (whole("[A-Za-z0-9.+_-]+@[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)+", target)) href <- paste0("mailto:", target)
          if (!is.null(href)) {
            pieces[[length(pieces) + 1L]] <- paste0('<a href="', escape_html(href), '">', escape_html(target), '</a>')
            at <- close + 1L
            next
          }
        }
      }
      if (links && (at == 1L || has(" \n*_~(", char_at(text, at - 1L)))) {
        found <- match_parts("\\Ahttps?://[^ \n<]*", slice(text, at))
        if (!is.null(found)) {
          url <- sub("[.,:;!?*_~)]+\\z", "", found[1L], perl = TRUE)
          if (!(url %in% c("http://", "https://"))) {
            pieces[[length(pieces) + 1L]] <- paste0('<a href="', escape_html(url), '">', escape_html(url), '</a>')
            at <- at + nchar(url)
            next
          }
        }
      }
      if (char == "[" || (char == "!" && following == "[")) {
        if (links && notes && starts(text, "[^", at)) {
          offset <- regexpr("]", slice(text, at + 2L), fixed = TRUE)[1L]
          if (offset > 0L) {
            close <- at + offset + 1L
            name <- tolower(slice(text, at + 2L, close))
            if (!is.null(lookup(footnotes, name))) {
              pieces[[length(pieces) + 1L]] <- footnote_reference(name)
              at <- close + 1L
              next
            }
          }
        }
        image <- char == "!"
        opening <- at + as.integer(image)
        close <- if (image || links) closing_bracket(text, opening) else NULL
        if (!is.null(close)) {
          label <- slice(text, opening + 1L, close)
          dest <- destination(text, close + 1L, label)
          if (!is.null(dest)) {
            reference <- dest[[1L]]
            title <- if (is.null(reference$title)) "" else paste0(' title="', escape_html(reference$title), '"')
            content <- inline(label, FALSE, FALSE)
            pieces[[length(pieces) + 1L]] <- if (image)
              paste0('<img src="', escape_html(reference$url), '" alt="', strip_tags(content), '"', title, ' />') else
              paste0('<a href="', escape_html(reference$url), '"', title, '>', content, '</a>')
            at <- dest[[2L]]
            next
          }
        }
      }
      if (has("*_~", char)) {
        end <- run_end(text, at)
        length <- end - at
        before <- if (at == 1L) " " else char_at(text, at - 1L)
        after <- if (end > nchar(text)) " " else char_at(text, end)
        can_open <- !has(whitespace, after)
        can_close <- !has(whitespace, before)
        if (char == "_" && whole("[A-Za-z0-9]", before) && whole("[A-Za-z0-9]", after)) can_open <- can_close <- FALSE
        piece <- if ((char != "~" && length <= 3L) || (char == "~" && length == 2L))
          list(char = char, length = length, can_open = can_open, can_close = can_close) else strrep(char, length)
        pieces[[length(pieces) + 1L]] <- piece
        at <- end
      } else {
        pieces[[length(pieces) + 1L]] <- escape_html(char)
        at <- at + 1L
      }
    }
    emphasis(pieces)
  }

  heading <- function(level, text) {
    matches <- gregexpr(" {#", text, fixed = TRUE)[[1L]]
    start <- tail(matches, 1L)
    candidate <- if (start > 0L && endsWith(text, "}")) slice(text, start + 3L, nchar(text)) else ""
    if (whole("[A-Za-z0-9_-]+", candidate)) {
      id <- candidate
      text <- right_trim(slice(text, 1L, start))
    } else {
      base <- gsub("[^a-z0-9_ \n-]", "", tolower(text), perl = TRUE)
      base <- gsub("[ \n]", "-", base)
      if (!nzchar(base)) base <- "heading"
      id <- base
      suffix <- 1L
      while (!is.null(state$used_ids[[id]])) {
        id <- paste0(base, "-", suffix)
        suffix <- suffix + 1L
      }
    }
    state$used_ids[[id]] <- TRUE
    html <- inline(text)
    state$headings[[length(state$headings) + 1L]] <- list(level = level, id = id, label = strip_tags(html), children = integer())
    paste0("<h", level, ' id="', id, '">', html, "</h", level, ">")
  }
  render_blocks <- function(blocks) paste0(vapply(blocks, function(block) paste0(render(block), "\n"), character(1L)), collapse = "")
  render_item <- function(blocks) {
    html <- "<li>"
    for (index in seq_along(blocks)) {
      block <- blocks[[index]]
      if (block$kind == "paragraph") {
        text <- block$text
        if (index == 1L && nchar(text) > 4L && substr(text, 1L, 4L) %in% c("[ ] ", "[x] ", "[X] ")) {
          checked <- if (char_at(text, 2L) == " ") "" else ' checked=""'
          html <- paste0(html, '<input type="checkbox"', checked, ' disabled="" /> ')
          text <- slice(text, 5L)
        }
        html <- paste0(html, inline(text))
      } else {
        if (!endsWith(html, "\n")) html <- paste0(html, "\n")
        html <- paste0(html, render(block), "\n")
      }
    }
    paste0(html, "</li>")
  }
  table_cells <- function(tag, table, cells) {
    paste0(vapply(seq_along(cells), function(index) {
      alignment <- table$alignments[index]
      style <- if (nzchar(alignment)) paste0(' style="text-align:', alignment, '"') else ""
      paste0("<", tag, style, ">", inline(cells[index]), "</", tag, ">\n")
    }, character(1L)), collapse = "")
  }
  render <- function(block) {
    switch(block$kind,
      heading = heading(block$number, block$text),
      paragraph = paste0("<p>", inline(block$text), "</p>"),
      rule = "<hr />",
      code = {
        attribute <- if (nzchar(block$text)) paste0(' class="language-', escape_html(block$text), '"') else ""
        code <- paste0(vapply(block$lines, function(line) paste0(escape_html(line), "\n"), character(1L)), collapse = "")
        paste0("<pre><code", attribute, ">", code, "</code></pre>")
      },
      quote = paste0("<blockquote>\n", render_blocks(block$children), "</blockquote>"),
      alert = {
        kind <- tolower(block$text)
        title <- paste0(toupper(char_at(kind, 1L)), slice(kind, 2L))
        paste0('<div class="alert alert-', kind, '">\n<p class="alert-title">', title, "</p>\n", render_blocks(block$children), "</div>")
      },
      list = {
        tag <- if (block$ordered) "ol" else "ul"
        attribute <- if (block$ordered && block$number != 1L) paste0(' start="', block$number, '"') else ""
        items <- paste0(vapply(block$items, function(item) paste0(render_item(item), "\n"), character(1L)), collapse = "")
        paste0("<", tag, attribute, ">\n", items, "</", tag, ">")
      },
      table = {
        html <- paste0("<table>\n<thead>\n<tr>\n", table_cells("th", block, block$lines), "</tr>\n</thead>\n")
        if (length(block$rows)) {
          html <- paste0(html, "<tbody>\n")
          for (row in block$rows) html <- paste0(html, "<tr>\n", table_cells("td", block, row), "</tr>\n")
          html <- paste0(html, "</tbody>\n")
        }
        paste0(html, "</table>")
      },
      toc = toc_marker
    )
  }
  toc_list <- function(indices) {
    html <- "<ul>\n"
    for (index in indices) {
      entry <- state$headings[[index]]
      html <- paste0(html, '<li><a href="#', entry$id, '">', entry$label, '</a>')
      if (length(entry$children)) html <- paste0(html, "\n", toc_list(entry$children), "\n")
      html <- paste0(html, "</li>\n")
    }
    paste0(html, "</ul>")
  }
  table_of_contents <- function() {
    if (!length(state$headings)) return('<nav class="toc">\n</nav>')
    roots <- integer()
    parents <- integer()
    for (index in seq_along(state$headings)) {
      entry <- state$headings[[index]]
      while (length(parents) && state$headings[[tail(parents, 1L)]]$level >= entry$level) parents <- head(parents, -1L)
      if (!length(parents)) roots <- c(roots, index) else {
        parent <- tail(parents, 1L)
        state$headings[[parent]]$children <- c(state$headings[[parent]]$children, index)
      }
      parents <- c(parents, index)
    }
    paste0('<nav class="toc">\n', toc_list(roots), "\n</nav>")
  }
  footnote_list <- function() {
    html <- '<section class="footnotes">\n<ol>\n'
    for (name in names(state$note_numbers)) {
      number <- state$note_numbers[[name]]
      body <- inline(footnotes[[name]], notes = FALSE)
      backlinks <- vapply(seq_len(state$note_counts[[name]]), function(count) {
        paste0('<a href="#', reference_id(number, count), '">&#8617;</a>')
      }, character(1L))
      html <- paste0(html, '<li id="fn-', number, '">', body, " ", paste(backlinks, collapse = " "), "</li>\n")
    }
    paste0(html, "</ol>\n</section>\n")
  }
  document <- function(blocks) {
    html <- render_blocks(blocks)
    contents <- table_of_contents()
    html <- paste(strsplit(html, toc_marker, fixed = TRUE)[[1L]], collapse = contents)
    if (length(state$note_numbers)) html <- paste0(html, footnote_list())
    html
  }
  document
}

lines <- readLines(file("stdin"), warn = FALSE)
terminator <- match("@@END@@", lines)
if (!is.na(terminator)) lines <- head(lines, terminator - 1L)
parser <- new_block_parser()
blocks <- parser$parse(lines)
render_document <- new_renderer(parser$state$references, parser$state$footnotes)
cat(render_document(blocks), sep = "")
