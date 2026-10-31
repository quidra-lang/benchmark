DATA_COMMANDS <- c("FILE", "PATCH", "EDIT")
FORMATS_WITH_ARGUMENT <- c("IFDEF", "UNIFIED", "CONTEXT", "SIDE")
OFFSETS <- c(0, 1, -1, 2, -2, 3, -3)
GRAPH_WIDTH <- 20
NUMBER_PAIR <- "^[0-9]{1,4}(,[0-9]{1,4})?$"
MARKER_PREFIXES <- c("<<<<<<<" = "start", "|||||||" = "base", ">>>>>>>" = "end")
SEPARATOR <- "======="

fail <- function(message) {
  stop(errorCondition(message, class = "command_error", call = NULL))
}

slice_lines <- function(lines, start, count) {
  lines[start + seq_len(count)]
}

prefixed <- function(prefix, lines) {
  paste0(prefix, lines, recycle0 = TRUE)
}

range_r <- function(start, count) {
  if (count >= 2) {
    paste0(start + 1, ",", start + count)
  } else if (count == 1) {
    as.character(start + 1)
  } else {
    as.character(start)
  }
}

range_u <- function(start, count) {
  if (count >= 2) {
    paste0(start + 1, ",", count)
  } else if (count == 1) {
    as.character(start + 1)
  } else {
    paste0(start, ",0")
  }
}

range_m <- function(start, count) {
  paste0(start + 1, ",", count)
}

comparison_keys <- function(lines, options) {
  if ("ICASE" %in% options) {
    lines <- tolower(lines)
  }
  if ("IWHITE" %in% options) {
    lines <- gsub(" ", "", lines, fixed = TRUE)
  }
  if ("ISPACE" %in% options) {
    lines <- gsub(" {2,}", " ", lines)
  }
  lines
}

matched_pairs <- function(first, second) {
  rows <- length(first)
  columns <- length(second)
  equal <- outer(first, second, "==")
  table <- matrix(0, rows + 1, columns + 1)
  for (i in seq_len(rows)) {
    for (j in seq_len(columns)) {
      if (equal[i, j]) {
        table[i + 1, j + 1] <- table[i, j] + 1
      } else {
        table[i + 1, j + 1] <- max(table[i, j + 1], table[i + 1, j])
      }
    }
  }
  old_indices <- rows + 1
  new_indices <- columns + 1
  i <- rows
  j <- columns
  while (i >= 1 && j >= 1) {
    if (equal[i, j]) {
      old_indices <- c(old_indices, i)
      new_indices <- c(new_indices, j)
      i <- i - 1
      j <- j - 1
    } else if (table[i, j + 1] >= table[i + 1, j]) {
      i <- i - 1
    } else {
      j <- j - 1
    }
  }
  list(old = rev(c(old_indices, 0)), new = rev(c(new_indices, 0)))
}

change_block <- function(p, q, x, y) {
  list(p = p, q = q, x = x, y = y)
}

block_letter <- function(block) {
  if (block$x >= 1 && block$y >= 1) {
    "c"
  } else if (block$y == 0) {
    "d"
  } else {
    "a"
  }
}

change_blocks <- function(first, second) {
  pairs <- matched_pairs(first, second)
  blocks <- list()
  for (k in seq_len(length(pairs$old) - 1)) {
    deleted <- pairs$old[k + 1] - pairs$old[k] - 1
    inserted <- pairs$new[k + 1] - pairs$new[k] - 1
    if (deleted > 0 || inserted > 0) {
      blocks[[length(blocks) + 1]] <- change_block(pairs$old[k], pairs$new[k], deleted, inserted)
    }
  }
  blocks
}

walk_step <- function(old_index, new_index, block = NULL) {
  list(old_index = old_index, new_index = new_index, block = block)
}

walk_steps <- function(blocks, old_start, new_start, old_end) {
  steps <- list()
  old_index <- old_start
  new_index <- new_start
  for (block in blocks) {
    while (old_index < block$p) {
      steps[[length(steps) + 1]] <- walk_step(old_index, new_index)
      old_index <- old_index + 1
      new_index <- new_index + 1
    }
    steps[[length(steps) + 1]] <- walk_step(old_index, new_index, block)
    old_index <- block$p + block$x
    new_index <- block$q + block$y
  }
  while (old_index < old_end) {
    steps[[length(steps) + 1]] <- walk_step(old_index, new_index)
    old_index <- old_index + 1
    new_index <- new_index + 1
  }
  steps
}

side_row <- function(left, symbol, right, width) {
  row <- sprintf("%-*s %s %s", width, substr(left, 1, width), symbol, substr(right, 1, width))
  sub(" +$", "", row)
}

stat_graph <- function(inserted, deleted) {
  total <- inserted + deleted
  plus <- inserted
  minus <- deleted
  if (total > GRAPH_WIDTH) {
    plus <- (GRAPH_WIDTH * inserted) %/% total
    minus <- (GRAPH_WIDTH * deleted) %/% total
    if (inserted >= 1 && plus == 0) {
      plus <- 1
    }
    if (deleted >= 1 && minus == 0) {
      minus <- 1
    }
  }
  paste0(strrep("+", plus), strrep("-", minus))
}

make_hunk <- function(blocks, context, old_total) {
  first <- blocks[[1]]
  last <- blocks[[length(blocks)]]
  before <- min(context, first$p)
  after <- min(context, old_total - last$p - last$x)
  old_start <- first$p - before
  new_start <- first$q - before
  list(
    blocks = blocks,
    old_start = old_start,
    old_count = last$p + last$x + after - old_start,
    new_start = new_start,
    new_count = last$q + last$y + after - new_start
  )
}

hunk_steps <- function(hunk) {
  walk_steps(hunk$blocks, hunk$old_start, hunk$new_start, hunk$old_start + hunk$old_count)
}

line_diff <- function(old_lines, new_lines, options = character(0)) {
  blocks <- change_blocks(comparison_keys(old_lines, options), comparison_keys(new_lines, options))
  list(old_lines = old_lines, new_lines = new_lines, blocks = blocks)
}

deleted_lines <- function(changes, block) {
  slice_lines(changes$old_lines, block$p, block$x)
}

inserted_lines <- function(changes, block) {
  slice_lines(changes$new_lines, block$q, block$y)
}

group_hunks <- function(changes, context) {
  groups <- list()
  for (block in changes$blocks) {
    count <- length(groups)
    if (count > 0) {
      group <- groups[[count]]
      previous <- group[[length(group)]]
      if (block$p - (previous$p + previous$x) <= 2 * context) {
        groups[[count]] <- c(group, list(block))
        next
      }
    }
    groups[[count + 1]] <- list(block)
  }
  lapply(groups, make_hunk, context = context, old_total = length(changes$old_lines))
}

normal_diff <- function(changes) {
  lines <- character(0)
  for (block in changes$blocks) {
    letter <- block_letter(block)
    lines <- c(lines, paste0(range_r(block$p, block$x), letter, range_r(block$q, block$y)))
    lines <- c(lines, prefixed("< ", deleted_lines(changes, block)))
    if (letter == "c") {
      lines <- c(lines, "---")
    }
    lines <- c(lines, prefixed("> ", inserted_lines(changes, block)))
  }
  lines
}

ed_script <- function(changes) {
  lines <- character(0)
  for (block in rev(changes$blocks)) {
    letter <- block_letter(block)
    lines <- c(lines, paste0(range_r(block$p, block$x), letter))
    if (letter != "d") {
      lines <- c(lines, inserted_lines(changes, block), ".")
    }
  }
  lines
}

rcs_diff <- function(changes) {
  lines <- character(0)
  for (block in changes$blocks) {
    if (block$x >= 1) {
      lines <- c(lines, sprintf("d%d %d", block$p + 1, block$x))
    }
    if (block$y >= 1) {
      lines <- c(lines, sprintf("a%d %d", block$p + block$x, block$y))
      lines <- c(lines, inserted_lines(changes, block))
    }
  }
  lines
}

ifdef_diff <- function(changes, macro) {
  lines <- character(0)
  for (step in walk_steps(changes$blocks, 0, 0, length(changes$old_lines))) {
    block <- step$block
    if (is.null(block)) {
      lines <- c(lines, changes$old_lines[step$old_index + 1])
    } else if (block$x >= 1 && block$y >= 1) {
      lines <- c(
        lines,
        paste("#ifndef", macro),
        deleted_lines(changes, block),
        sprintf("#else /* %s */", macro),
        inserted_lines(changes, block),
        sprintf("#endif /* %s */", macro)
      )
    } else if (block$y == 0) {
      lines <- c(
        lines,
        paste("#ifndef", macro),
        deleted_lines(changes, block),
        sprintf("#endif /* ! %s */", macro)
      )
    } else {
      lines <- c(
        lines,
        paste("#ifdef", macro),
        inserted_lines(changes, block),
        sprintf("#endif /* %s */", macro)
      )
    }
  }
  lines
}

unified_diff <- function(changes, context, old_name, new_name) {
  lines <- c(paste("---", old_name), paste("+++", new_name))
  for (hunk in group_hunks(changes, context)) {
    old_range <- range_u(hunk$old_start, hunk$old_count)
    new_range <- range_u(hunk$new_start, hunk$new_count)
    lines <- c(lines, sprintf("@@ -%s +%s @@", old_range, new_range))
    for (step in hunk_steps(hunk)) {
      if (is.null(step$block)) {
        lines <- c(lines, paste0(" ", changes$old_lines[step$old_index + 1]))
      } else {
        lines <- c(lines, prefixed("-", deleted_lines(changes, step$block)))
        lines <- c(lines, prefixed("+", inserted_lines(changes, step$block)))
      }
    }
  }
  lines
}

context_diff <- function(changes, context, old_name, new_name) {
  lines <- c(paste("***", old_name), paste("---", new_name))
  for (hunk in group_hunks(changes, context)) {
    lines <- c(lines, strrep("*", 15))
    lines <- c(lines, sprintf("*** %s ****", range_r(hunk$old_start, hunk$old_count)))
    if (any(vapply(hunk$blocks, function(block) block$x >= 1, logical(1)))) {
      for (step in hunk_steps(hunk)) {
        if (is.null(step$block)) {
          lines <- c(lines, paste0("  ", changes$old_lines[step$old_index + 1]))
        } else {
          marker <- if (step$block$y >= 1) "! " else "- "
          lines <- c(lines, prefixed(marker, deleted_lines(changes, step$block)))
        }
      }
    }
    lines <- c(lines, sprintf("--- %s ----", range_r(hunk$new_start, hunk$new_count)))
    if (any(vapply(hunk$blocks, function(block) block$y >= 1, logical(1)))) {
      for (step in hunk_steps(hunk)) {
        if (is.null(step$block)) {
          lines <- c(lines, paste0("  ", changes$new_lines[step$new_index + 1]))
        } else {
          marker <- if (step$block$x >= 1) "! " else "+ "
          lines <- c(lines, prefixed(marker, inserted_lines(changes, step$block)))
        }
      }
    }
  }
  lines
}

side_by_side <- function(changes, width) {
  lines <- character(0)
  for (step in walk_steps(changes$blocks, 0, 0, length(changes$old_lines))) {
    block <- step$block
    if (is.null(block)) {
      left <- changes$old_lines[step$old_index + 1]
      right <- changes$new_lines[step$new_index + 1]
      lines <- c(lines, side_row(left, " ", right, width))
      next
    }
    for (row in seq_len(max(block$x, block$y))) {
      if (row <= block$x && row <= block$y) {
        left <- changes$old_lines[block$p + row]
        symbol <- "|"
        right <- changes$new_lines[block$q + row]
      } else if (row <= block$x) {
        left <- changes$old_lines[block$p + row]
        symbol <- "<"
        right <- ""
      } else {
        left <- ""
        symbol <- ">"
        right <- changes$new_lines[block$q + row]
      }
      lines <- c(lines, side_row(left, symbol, right, width))
    }
  }
  lines
}

split_tokens <- function(line, by_word) {
  strsplit(line, if (by_word) " +" else "")[[1]]
}

deletion <- function(tokens, separator) {
  paste0("[-", paste(tokens, collapse = separator), "-]")
}

insertion <- function(tokens, separator) {
  paste0("{+", paste(tokens, collapse = separator), "+}")
}

compare_tokens <- function(old_tokens, new_tokens, separator) {
  parts <- character(0)
  counts <- c(deleted = 0, inserted = 0, common = 0)
  for (step in walk_steps(change_blocks(old_tokens, new_tokens), 0, 0, length(old_tokens))) {
    block <- step$block
    if (is.null(block)) {
      parts <- c(parts, old_tokens[step$old_index + 1])
      counts[["common"]] <- counts[["common"]] + 1
      next
    }
    if (block$x >= 1) {
      parts <- c(parts, deletion(slice_lines(old_tokens, block$p, block$x), separator))
    }
    if (block$y >= 1) {
      parts <- c(parts, insertion(slice_lines(new_tokens, block$q, block$y), separator))
    }
    counts[["deleted"]] <- counts[["deleted"]] + block$x
    counts[["inserted"]] <- counts[["inserted"]] + block$y
  }
  list(text = paste(parts, collapse = separator), counts = counts)
}

hunk_sequences <- function(hunk, reverse) {
  old_kind <- if (reverse) "+" else "-"
  new_kind <- if (reverse) "-" else "+"
  list(
    old = hunk$texts[hunk$kinds %in% c(" ", old_kind)],
    new = hunk$texts[hunk$kinds %in% c(" ", new_kind)]
  )
}

hunk_start <- function(hunk, reverse) {
  if (reverse) hunk$new_start else hunk$old_start
}

leading_context <- function(hunk) {
  min(which(hunk$kinds != " ")) - 1
}

trailing_context <- function(hunk) {
  length(hunk$kinds) - max(which(hunk$kinds != " "))
}

hunk_report <- function(found, number) {
  text <- sprintf("Hunk #%d succeeded at %d", number, found$position + 1)
  if (found$fuzz >= 1) {
    text <- paste(text, "with fuzz", found$fuzz)
  }
  if (abs(found$delta) == 1) {
    text <- sprintf("%s (offset %d line)", text, found$delta)
  } else if (found$delta != 0) {
    text <- sprintf("%s (offset %d lines)", text, found$delta)
  }
  text
}

parse_number_pair <- function(text) {
  if (!grepl(NUMBER_PAIR, text)) {
    return(NULL)
  }
  as.integer(strsplit(text, ",", fixed = TRUE)[[1]])
}

parse_range <- function(text, sign) {
  if (!startsWith(text, sign)) {
    return(NULL)
  }
  numbers <- parse_number_pair(substring(text, 2))
  if (is.null(numbers)) {
    return(NULL)
  }
  start <- numbers[1]
  count <- if (length(numbers) == 2) numbers[2] else 1L
  if (start == 0 && count != 0) {
    return(NULL)
  }
  c(start, count)
}

parse_hunk_header <- function(line, line_number) {
  parts <- strsplit(line, " ", fixed = TRUE)[[1]]
  old_range <- NULL
  new_range <- NULL
  if (length(parts) == 4 && parts[1] == "@@" && parts[4] == "@@") {
    old_range <- parse_range(parts[2], "-")
    new_range <- parse_range(parts[3], "+")
  }
  if (is.null(old_range) || is.null(new_range)) {
    fail(sprintf("PATCH ERROR line %d: bad hunk header", line_number))
  }
  list(
    line_number = line_number,
    old_start = old_range[1],
    old_count = old_range[2],
    new_start = new_range[1],
    new_count = new_range[2]
  )
}

parse_patch <- function(patch_lines) {
  index <- match(TRUE, startsWith(patch_lines, "@@"))
  if (is.na(index)) {
    fail("PATCH ERROR no hunks")
  }
  hunks <- list()
  while (index <= length(patch_lines)) {
    hunk <- parse_hunk_header(patch_lines[index], index)
    index <- index + 1
    old_seen <- 0
    new_seen <- 0
    kinds <- character(0)
    texts <- character(0)
    while (old_seen < hunk$old_count || new_seen < hunk$new_count) {
      if (index > length(patch_lines)) {
        fail(sprintf("PATCH ERROR line %d: truncated hunk", hunk$line_number))
      }
      line <- patch_lines[index]
      kind <- substr(line, 1, 1)
      in_old <- kind %in% c(" ", "-")
      in_new <- kind %in% c(" ", "+")
      if (nchar(line) < 2 ||
        !(in_old || in_new) ||
        (in_old && old_seen == hunk$old_count) ||
        (in_new && new_seen == hunk$new_count)) {
        fail(sprintf("PATCH ERROR line %d: bad hunk line", index))
      }
      kinds <- c(kinds, kind)
      texts <- c(texts, substring(line, 2))
      if (in_old) {
        old_seen <- old_seen + 1
      }
      if (in_new) {
        new_seen <- new_seen + 1
      }
      index <- index + 1
    }
    if (all(kinds == " ")) {
      fail(sprintf("PATCH ERROR line %d: no changes", hunk$line_number))
    }
    hunk$kinds <- kinds
    hunk$texts <- texts
    hunks[[length(hunks) + 1]] <- hunk
  }
  hunks
}

search_hunk <- function(hunk, lines, adjustment, reverse, max_fuzz) {
  sequences <- hunk_sequences(hunk, reverse)
  old_sequence <- sequences$old
  new_sequence <- sequences$new
  start <- hunk_start(hunk, reverse)
  expected <- if (length(old_sequence) > 0) start - 1 + adjustment else start + adjustment
  leading <- leading_context(hunk)
  trailing <- trailing_context(hunk)
  for (fuzz in 0:max_fuzz) {
    front <- min(fuzz, leading)
    back <- min(fuzz, trailing)
    old_part <- slice_lines(old_sequence, front, length(old_sequence) - front - back)
    new_part <- slice_lines(new_sequence, front, length(new_sequence) - front - back)
    for (delta in OFFSETS) {
      position <- expected + front + delta
      end <- position + length(old_part)
      if (position < 0 || end > length(lines)) {
        next
      }
      if (identical(slice_lines(lines, position, length(old_part)), old_part)) {
        result <- c(
          slice_lines(lines, 0, position),
          new_part,
          slice_lines(lines, end, length(lines) - end)
        )
        return(list(fuzz = fuzz, delta = delta, position = position, lines = result))
      }
    }
  }
  NULL
}

parse_edit_command <- function(line) {
  size <- nchar(line)
  instruction <- substr(line, size, size)
  numbers <- parse_number_pair(substr(line, 1, size - 1))
  if (!(instruction %in% c("a", "c", "d")) || is.null(numbers)) {
    return(NULL)
  }
  if (instruction == "a" && length(numbers) == 2) {
    return(NULL)
  }
  list(instruction = instruction, first = numbers[1], last = numbers[length(numbers)])
}

run_edit_script <- function(lines, script) {
  executed <- 0
  index <- 1
  while (index <= length(script)) {
    line_number <- index
    command <- parse_edit_command(script[index])
    if (is.null(command)) {
      fail(sprintf("EDIT ERROR line %d: bad command", line_number))
    }
    first <- command$first
    last <- command$last
    if (command$instruction == "a") {
      valid <- first <= length(lines)
    } else {
      valid <- 1 <= first && first <= last && last <= length(lines)
    }
    if (!valid) {
      fail(sprintf("EDIT ERROR line %d: bad range", line_number))
    }
    index <- index + 1
    text <- character(0)
    if (command$instruction %in% c("a", "c")) {
      terminators <- which(script == ".")
      terminator <- terminators[terminators >= index][1]
      if (is.na(terminator)) {
        fail(sprintf("EDIT ERROR line %d: missing terminator", line_number))
      }
      text <- slice_lines(script, index - 1, terminator - index)
      index <- terminator + 1
    }
    lines <- switch(command$instruction,
      a = append(lines, text, after = first),
      c = append(lines[-(first:last)], text, after = first - 1),
      d = lines[-(first:last)]
    )
    executed <- executed + 1
  }
  list(lines = lines, executed = executed)
}

make_chunk <- function(kind, base_start, ours_start, theirs_start, base, ours, theirs) {
  list(
    kind = kind,
    base_start = base_start,
    ours_start = ours_start,
    theirs_start = theirs_start,
    base = base,
    ours = ours,
    theirs = theirs
  )
}

chunk_location <- function(chunk) {
  sprintf(
    "base %s a %s b %s",
    range_m(chunk$base_start, length(chunk$base)),
    range_m(chunk$ours_start, length(chunk$ours)),
    range_m(chunk$theirs_start, length(chunk$theirs))
  )
}

chunk_kind <- function(base, ours, theirs) {
  if (identical(ours, base)) {
    "b"
  } else if (identical(theirs, base)) {
    "a"
  } else if (identical(ours, theirs)) {
    "both"
  } else {
    "conflict"
  }
}

match_table <- function(first, second) {
  pairs <- matched_pairs(first, second)
  inner <- seq_len(length(pairs$old) - 2) + 1
  matches <- integer(length(first))
  matches[pairs$old[inner]] <- pairs$new[inner]
  matches
}

three_way_chunks <- function(base, ours, theirs) {
  ours_match <- match_table(base, ours)
  theirs_match <- match_table(base, theirs)
  anchors <- which(ours_match > 0 & theirs_match > 0)
  chunks <- list()
  x <- 0
  y <- 0
  z <- 0
  while (x < length(base) || y < length(ours) || z < length(theirs)) {
    if (x < length(base) && ours_match[x + 1] == y + 1 && theirs_match[x + 1] == z + 1) {
      chunk <- make_chunk("stable", x, y, z, base[x + 1], ours[y + 1], theirs[z + 1])
      chunks[[length(chunks) + 1]] <- chunk
      x <- x + 1
      y <- y + 1
      z <- z + 1
      next
    }
    anchor <- anchors[anchors > x][1]
    if (!is.na(anchor)) {
      next_x <- anchor - 1
      next_y <- ours_match[anchor] - 1
      next_z <- theirs_match[anchor] - 1
    } else {
      next_x <- length(base)
      next_y <- length(ours)
      next_z <- length(theirs)
    }
    base_part <- slice_lines(base, x, next_x - x)
    ours_part <- slice_lines(ours, y, next_y - y)
    theirs_part <- slice_lines(theirs, z, next_z - z)
    kind <- chunk_kind(base_part, ours_part, theirs_part)
    chunks[[length(chunks) + 1]] <- make_chunk(kind, x, y, z, base_part, ours_part, theirs_part)
    x <- next_x
    y <- next_y
    z <- next_z
  }
  chunks
}

kind_counts <- function(chunks) {
  kinds <- vapply(chunks, function(chunk) chunk$kind, character(1))
  tally <- function(kind) sum(kinds == kind)
  sprintf(
    "a=%d b=%d both=%d conflicts=%d",
    tally("a"), tally("b"), tally("both"), tally("conflict")
  )
}

common_prefix_length <- function(first, second) {
  size <- 0
  while (size < min(length(first), length(second)) && first[size + 1] == second[size + 1]) {
    size <- size + 1
  }
  size
}

common_suffix_length <- function(first, second, limit) {
  size <- 0
  while (size < limit && first[length(first) - size] == second[length(second) - size]) {
    size <- size + 1
  }
  size
}

conflict_lines <- function(chunk, mode, base_name, ours_name, theirs_name) {
  ours <- chunk$ours
  theirs <- chunk$theirs
  if (mode == "OURS") {
    return(ours)
  }
  if (mode == "THEIRS") {
    return(theirs)
  }
  if (mode == "DIFF3") {
    return(c(
      paste("<<<<<<<", ours_name), ours, paste("|||||||", base_name), chunk$base,
      SEPARATOR, theirs, paste(">>>>>>>", theirs_name)
    ))
  }
  front <- common_prefix_length(ours, theirs)
  back <- common_suffix_length(ours, theirs, min(length(ours), length(theirs)) - front)
  ours_middle <- slice_lines(ours, front, length(ours) - front - back)
  theirs_middle <- slice_lines(theirs, front, length(theirs) - front - back)
  if (mode == "UNION") {
    middle <- c(ours_middle, theirs_middle)
  } else {
    middle <- c(
      paste("<<<<<<<", ours_name), ours_middle, SEPARATOR,
      theirs_middle, paste(">>>>>>>", theirs_name)
    )
  }
  c(slice_lines(ours, 0, front), middle, slice_lines(ours, length(ours) - back, back))
}

marker_kind <- function(line) {
  if (line == SEPARATOR) {
    return("separator")
  }
  prefix <- substr(line, 1, 7)
  if (prefix %in% names(MARKER_PREFIXES) && (nchar(line) == 7 || substr(line, 8, 8) == " ")) {
    return(MARKER_PREFIXES[[prefix]])
  }
  NA_character_
}

next_marker <- function(kinds, index) {
  markers <- which(!is.na(kinds))
  markers[markers > index][1]
}

is_marker <- function(kinds, index, kind) {
  !is.na(index) && identical(kinds[index], kind)
}

lines_between <- function(lines, after, before) {
  slice_lines(lines, after, before - after - 1)
}

region_at <- function(lines, kinds, start) {
  if (!is_marker(kinds, start, "start")) {
    return(NULL)
  }
  middle <- next_marker(kinds, start)
  base_marker <- NA
  if (is_marker(kinds, middle, "base")) {
    base_marker <- middle
    middle <- next_marker(kinds, middle)
  }
  if (!is_marker(kinds, middle, "separator")) {
    return(NULL)
  }
  end <- next_marker(kinds, middle)
  if (!is_marker(kinds, end, "end")) {
    return(NULL)
  }
  if (is.na(base_marker)) {
    ours <- lines_between(lines, start, middle)
    base <- NULL
  } else {
    ours <- lines_between(lines, start, base_marker)
    base <- lines_between(lines, base_marker, middle)
  }
  theirs <- lines_between(lines, middle, end)
  list(start = start, end = end, ours = ours, base = base, theirs = theirs)
}

conflict_regions <- function(lines) {
  kinds <- vapply(lines, marker_kind, character(1), USE.NAMES = FALSE)
  regions <- list()
  index <- 1
  while (index <= length(lines)) {
    region <- region_at(lines, kinds, index)
    if (is.null(region)) {
      index <- index + 1
    } else {
      regions[[length(regions) + 1]] <- region
      index <- region$end + 1
    }
  }
  regions
}

region_part <- function(region, side) {
  switch(side,
    OURS = region$ours,
    THEIRS = region$theirs,
    BASE = region$base,
    BOTH = c(region$ours, region$theirs)
  )
}

new_workspace <- function() {
  workspace <- new.env()
  workspace$files <- list()
  workspace$history <- list()
  workspace
}

require_files <- function(workspace, ...) {
  for (name in c(...)) {
    if (!(name %in% names(workspace$files))) {
      fail(paste("ERROR no such file", name))
    }
  }
}

save_file <- function(workspace, name, lines) {
  workspace$history[[name]] <- c(workspace$history[[name]], list(workspace$files[[name]]))
  workspace$files[[name]] <- lines
}

file_command <- function(workspace, arguments, data) {
  name <- arguments[1]
  save_file(workspace, name, data)
  writeLines(sprintf("FILE %s lines=%d", name, length(data)))
}

copy_command <- function(workspace, arguments) {
  source <- arguments[1]
  target <- arguments[2]
  require_files(workspace, source)
  lines <- workspace$files[[source]]
  save_file(workspace, target, lines)
  writeLines(sprintf("COPY %s %s lines=%d", source, target, length(lines)))
}

print_command <- function(workspace, arguments) {
  name <- arguments[1]
  require_files(workspace, name)
  lines <- workspace$files[[name]]
  writeLines(sprintf("PRINT %s lines=%d", name, length(lines)))
  writeLines(sprintf("%3d| %s", seq_along(lines), lines))
}

files_command <- function(workspace, arguments) {
  writeLines(sprintf("FILES count=%d", length(workspace$files)))
  for (name in sort(as.character(names(workspace$files)), method = "radix")) {
    writeLines(sprintf(
      "%s lines=%d undo=%d",
      name, length(workspace$files[[name]]), length(workspace$history[[name]])
    ))
  }
}

undo_command <- function(workspace, arguments) {
  name <- arguments[1]
  states <- workspace$history[[name]]
  if (length(states) == 0) {
    fail(paste("ERROR nothing to undo", name))
  }
  state <- states[[length(states)]]
  workspace$history[[name]] <- states[-length(states)]
  if (is.null(state)) {
    workspace$files[[name]] <- NULL
    writeLines(sprintf("UNDO %s removed", name))
  } else {
    workspace$files[[name]] <- state
    writeLines(sprintf("UNDO %s lines=%d", name, length(state)))
  }
}

diff_command <- function(workspace, arguments) {
  old_name <- arguments[1]
  new_name <- arguments[2]
  form <- arguments[3]
  require_files(workspace, old_name, new_name)
  parameter <- NULL
  options <- arguments[-(1:3)]
  if (form %in% FORMATS_WITH_ARGUMENT) {
    parameter <- arguments[4]
    options <- arguments[-(1:4)]
  }
  changes <- line_diff(workspace$files[[old_name]], workspace$files[[new_name]], options)
  if (length(changes$blocks) == 0) {
    writeLines(sprintf("Files %s and %s are identical", old_name, new_name))
    return(invisible())
  }
  writeLines(switch(form,
    BRIEF = sprintf("Files %s and %s differ", old_name, new_name),
    NORMAL = normal_diff(changes),
    ED = ed_script(changes),
    RCS = rcs_diff(changes),
    IFDEF = ifdef_diff(changes, parameter),
    UNIFIED = unified_diff(changes, as.integer(parameter), old_name, new_name),
    CONTEXT = context_diff(changes, as.integer(parameter), old_name, new_name),
    SIDE = side_by_side(changes, as.integer(parameter))
  ))
}

token_diff_command <- function(workspace, arguments, by_word) {
  old_name <- arguments[1]
  new_name <- arguments[2]
  require_files(workspace, old_name, new_name)
  old_lines <- workspace$files[[old_name]]
  new_lines <- workspace$files[[new_name]]
  changes <- line_diff(old_lines, new_lines)
  if (length(changes$blocks) == 0) {
    writeLines(sprintf("Files %s and %s are identical", old_name, new_name))
    return(invisible())
  }
  separator <- if (by_word) " " else ""
  totals <- c(deleted = 0, inserted = 0, common = 0)
  for (block in changes$blocks) {
    for (row in seq_len(max(block$x, block$y))) {
      old_number <- block$p + row
      new_number <- block$q + row
      if (row <= block$x && row <= block$y) {
        old_tokens <- split_tokens(old_lines[old_number], by_word)
        new_tokens <- split_tokens(new_lines[new_number], by_word)
        result <- compare_tokens(old_tokens, new_tokens, separator)
        totals <- totals + result$counts
        writeLines(sprintf("a%d b%d: %s", old_number, new_number, result$text))
      } else if (row <= block$x) {
        old_tokens <- split_tokens(old_lines[old_number], by_word)
        totals[["deleted"]] <- totals[["deleted"]] + length(old_tokens)
        writeLines(sprintf("a%d: %s", old_number, deletion(old_tokens, separator)))
      } else {
        new_tokens <- split_tokens(new_lines[new_number], by_word)
        totals[["inserted"]] <- totals[["inserted"]] + length(new_tokens)
        writeLines(sprintf("b%d: %s", new_number, insertion(new_tokens, separator)))
      }
    }
  }
  label <- if (by_word) "WORDS" else "CHARS"
  writeLines(sprintf(
    "%s deleted=%d inserted=%d common=%d",
    label, totals[["deleted"]], totals[["inserted"]], totals[["common"]]
  ))
}

stat_command <- function(workspace, arguments) {
  old_name <- arguments[1]
  new_name <- arguments[2]
  require_files(workspace, old_name, new_name)
  old_lines <- workspace$files[[old_name]]
  new_lines <- workspace$files[[new_name]]
  changes <- line_diff(old_lines, new_lines, arguments[-(1:2)])
  deleted <- sum(vapply(changes$blocks, function(block) block$x, numeric(1)))
  inserted <- sum(vapply(changes$blocks, function(block) block$y, numeric(1)))
  total <- deleted + inserted
  unchanged <- length(old_lines) - deleted
  summary <- sprintf("%s -> %s | %d", old_name, new_name, total)
  if (total > 0) {
    summary <- paste(summary, stat_graph(inserted, deleted))
  }
  writeLines(summary)
  line_total <- length(old_lines) + length(new_lines)
  similarity <- if (line_total > 0) (200 * unchanged) %/% line_total else 100
  writeLines(sprintf(
    "changes=%d insertions=%d deletions=%d unchanged=%d similarity=%d%%",
    length(changes$blocks), inserted, deleted, unchanged, similarity
  ))
}

patch_command <- function(workspace, arguments, data) {
  name <- arguments[1]
  require_files(workspace, name)
  options <- arguments[-(1:2)]
  reverse <- "REVERSE" %in% options
  dry_run <- "DRYRUN" %in% options
  fuzz_index <- match("FUZZ", options)
  max_fuzz <- if (is.na(fuzz_index)) 0 else as.integer(options[fuzz_index + 1])
  hunks <- parse_patch(data)
  writeLines(paste(if (dry_run) "checking file" else "patching file", name))
  lines <- workspace$files[[name]]
  first <- hunks[[1]]
  if (is.null(search_hunk(first, lines, 0, reverse, max_fuzz)) &&
    !is.null(search_hunk(first, lines, 0, !reverse, max_fuzz))) {
    writeLines(c(
      "Reversed (or previously applied) patch detected! Skipping patch.",
      sprintf("RESULT applied=0 failed=0 ignored=%d lines=%d", length(hunks), length(lines))
    ))
    return(invisible())
  }
  adjustment <- 0
  applied <- 0
  failed <- 0
  for (number in seq_along(hunks)) {
    hunk <- hunks[[number]]
    found <- search_hunk(hunk, lines, adjustment, reverse, max_fuzz)
    if (is.null(found)) {
      failed <- failed + 1
      writeLines(sprintf("Hunk #%d FAILED at %d", number, hunk_start(hunk, reverse)))
      next
    }
    sequences <- hunk_sequences(hunk, reverse)
    lines <- found$lines
    adjustment <- adjustment + found$delta + length(sequences$new) - length(sequences$old)
    applied <- applied + 1
    writeLines(hunk_report(found, number))
  }
  writeLines(sprintf(
    "RESULT applied=%d failed=%d ignored=0 lines=%d", applied, failed, length(lines)
  ))
  if (!dry_run && applied >= 1) {
    save_file(workspace, name, lines)
  }
}

edit_command <- function(workspace, arguments, data) {
  name <- arguments[1]
  require_files(workspace, name)
  result <- run_edit_script(workspace$files[[name]], data)
  writeLines(sprintf("EDIT %s commands=%d lines=%d", name, result$executed, length(result$lines)))
  save_file(workspace, name, result$lines)
}

three_way <- function(workspace, base_name, ours_name, theirs_name) {
  require_files(workspace, base_name, ours_name, theirs_name)
  files <- workspace$files
  three_way_chunks(files[[base_name]], files[[ours_name]], files[[theirs_name]])
}

diff3_command <- function(workspace, arguments) {
  chunks <- three_way(workspace, arguments[1], arguments[2], arguments[3])
  changes <- Filter(function(chunk) chunk$kind != "stable", chunks)
  for (chunk in changes) {
    writeLines(sprintf("==== %s %s", chunk$kind, chunk_location(chunk)))
    writeLines(prefixed("O ", chunk$base))
    if (chunk$kind != "b") {
      writeLines(prefixed("A ", chunk$ours))
    }
    if (chunk$kind %in% c("b", "conflict")) {
      writeLines(prefixed("B ", chunk$theirs))
    }
  }
  writeLines(sprintf("DIFF3 chunks=%d %s", length(changes), kind_counts(chunks)))
}

merge_command <- function(workspace, arguments) {
  base_name <- arguments[1]
  ours_name <- arguments[2]
  theirs_name <- arguments[3]
  target <- arguments[4]
  mode <- if (length(arguments) == 5) arguments[5] else "MARKERS"
  chunks <- three_way(workspace, base_name, ours_name, theirs_name)
  result <- character(0)
  conflicts <- list()
  for (chunk in chunks) {
    if (chunk$kind == "b") {
      result <- c(result, chunk$theirs)
    } else if (chunk$kind == "conflict") {
      result <- c(result, conflict_lines(chunk, mode, base_name, ours_name, theirs_name))
      conflicts[[length(conflicts) + 1]] <- chunk
    } else {
      result <- c(result, chunk$ours)
    }
  }
  writeLines(sprintf("MERGE %s lines=%d %s", target, length(result), kind_counts(chunks)))
  for (number in seq_along(conflicts)) {
    writeLines(sprintf("CONFLICT %d %s", number, chunk_location(conflicts[[number]])))
  }
  save_file(workspace, target, result)
}

conflicts_command <- function(workspace, arguments) {
  name <- arguments[1]
  require_files(workspace, name)
  regions <- conflict_regions(workspace$files[[name]])
  writeLines(sprintf("CONFLICTS %s count=%d", name, length(regions)))
  for (number in seq_along(regions)) {
    region <- regions[[number]]
    base <- if (is.null(region$base)) "none" else length(region$base)
    writeLines(sprintf(
      "%d: lines %d-%d ours=%d base=%s theirs=%d",
      number, region$start, region$end, length(region$ours), base, length(region$theirs)
    ))
  }
}

resolve_command <- function(workspace, arguments) {
  name <- arguments[1]
  side <- arguments[3]
  require_files(workspace, name)
  number <- as.integer(arguments[2])
  lines <- workspace$files[[name]]
  regions <- conflict_regions(lines)
  if (length(regions) < number) {
    fail(sprintf("ERROR no conflict %d in %s", number, name))
  }
  region <- regions[[number]]
  if (side == "BASE" && is.null(region$base)) {
    fail(sprintf("ERROR no base section in conflict %d", number))
  }
  content <- c(
    slice_lines(lines, 0, region$start - 1),
    region_part(region, side),
    slice_lines(lines, region$end, length(lines) - region$end)
  )
  remaining <- length(conflict_regions(content))
  writeLines(sprintf(
    "RESOLVE %s %d %s lines=%d remaining=%d", name, number, side, length(content), remaining
  ))
  save_file(workspace, name, content)
}

HANDLERS <- list(
  FILE = file_command,
  COPY = copy_command,
  PRINT = print_command,
  FILES = files_command,
  DIFF = diff_command,
  WORDDIFF = function(workspace, arguments) token_diff_command(workspace, arguments, TRUE),
  CHARDIFF = function(workspace, arguments) token_diff_command(workspace, arguments, FALSE),
  STAT = stat_command,
  PATCH = patch_command,
  EDIT = edit_command,
  DIFF3 = diff3_command,
  MERGE = merge_command,
  CONFLICTS = conflicts_command,
  RESOLVE = resolve_command,
  UNDO = undo_command
)

execute <- function(workspace, words, data) {
  command <- words[1]
  arguments <- words[-1]
  handler <- HANDLERS[[command]]
  tryCatch(
    if (command %in% DATA_COMMANDS) {
      handler(workspace, arguments, data)
    } else {
      handler(workspace, arguments)
    },
    command_error = function(error) writeLines(conditionMessage(error))
  )
}

main <- function() {
  input <- readLines(file("stdin"), warn = FALSE)
  workspace <- new_workspace()
  position <- 2
  for (i in seq_len(as.integer(input[1]))) {
    words <- strsplit(input[position], " ", fixed = TRUE)[[1]]
    position <- position + 1
    data <- character(0)
    if (words[1] %in% DATA_COMMANDS) {
      count <- as.integer(words[3])
      data <- slice_lines(input, position - 1, count)
      position <- position + count
    }
    execute(workspace, words, data)
  }
}

main()
