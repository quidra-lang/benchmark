source("grid.R")
source("slots.R")
source("word_index.R")
source("filler.R")
source("render.R")

letter_points <- c(1L, 3L, 3L, 2L, 1L, 4L, 2L, 4L, 1L, 8L, 5L, 1L, 3L, 1L, 1L, 3L, 10L, 1L, 1L, 1L, 1L, 4L, 4L, 8L, 4L, 10L)
read_input_lines <- function(name) readLines(file.path("input", name), warn = FALSE)
ignored <- function(line) !nzchar(line) || startsWith(line, "#")
joined <- function(values, separator) if (!length(values)) "-" else paste(values, collapse = separator)

write_lines <- function(name, lines) writeLines(lines, file.path("output", name), useBytes = TRUE)
write_paragraphs <- function(name, paragraphs) {
  lines <- character()
  for (paragraph in paragraphs) {
    if (length(lines)) lines <- c(lines, "")
    lines <- c(lines, paragraph)
  }
  write_lines(name, lines)
}

read_settings <- function(lines) {
  values <- list()
  for (line in lines) {
    if (ignored(line)) next
    parts <- strsplit(line, " ", fixed = TRUE)[[1L]]
    values[[parts[1L]]] <- if (parts[1L] == "symmetry") parts[2L] else as.integer(parts[2L])
  }
  list(budget = values$node_budget, minimum = values$min_score, symmetry = values$symmetry, relax = values$relax_step, weak = values$weak_score)
}

new_word_list <- function(lines) {
  scores <- numeric()
  first_lines <- new.env(hash = TRUE, parent = emptyenv())
  invalid <- duplicates <- list()
  for (i in seq_along(lines)) {
    reason <- word_line_error(lines[i])
    if (nzchar(reason)) {
      invalid[[length(invalid) + 1L]] <- list(line = i, reason = reason)
      next
    }
    parts <- strsplit(lines[i], " ", fixed = TRUE)[[1L]]
    word <- parts[1L]
    first <- get0(word, first_lines, inherits = FALSE, ifnotfound = 0L)
    if (first) {
      duplicates[[length(duplicates) + 1L]] <- list(line = i, word = word, first = first)
    } else {
      scores[word] <- as.numeric(parts[2L])
      assign(word, i, first_lines)
    }
  }
  list(line_count = length(lines), index = new_word_index(scores), invalid = invalid, duplicates = duplicates)
}

word_report <- function(word_list) {
  index <- word_list$index
  lines <- sprintf("WORDLIST lines=%d valid=%d invalid=%d duplicates=%d", word_list$line_count, length(index$words), length(word_list$invalid), length(word_list$duplicates))
  for (issue in word_list$invalid) lines <- c(lines, paste("invalid", issue$line, issue$reason))
  for (duplicate in word_list$duplicates) lines <- c(lines, paste("duplicate", duplicate$line, duplicate$word, paste0("first=", duplicate$first)))
  for (size in seq_len(15L)) {
    words <- index$by_length[[size]]
    if (!length(words)) next
    total <- sum(index$scores[words])
    best <- words[1L]
    lines <- c(lines, sprintf("length %d words=%d average=%s best=%s:%d", size, length(words), decimal_text(total, length(words), 2L), index$words[best], index$scores[best]))
  }
  bands <- vapply(0:4, function(band) {
    low <- band * 20L + 1L
    high <- (band + 1L) * 20L
    paste0(low, "-", high, "=", sum(index$scores >= low & index$scores <= high))
  }, character(1))
  lines <- c(lines, paste("bands", paste(bands, collapse = " ")))
  top <- seq_len(min(5L, length(index$words)))
  lines <- c(lines, paste("top", paste(paste0(index$words[top], ":", index$scores[top]), collapse = " ")))
  rare_counts <- vapply(LETTERS, function(letter) sum(vapply(index$letters, function(word) letter %in% word, logical(1))), integer(1))
  rare <- order(rare_counts, seq_along(LETTERS), method = "radix")[seq_len(5L)]
  c(lines, paste("rare_letters", paste(paste0(LETTERS[rare], ":", rare_counts[rare]), collapse = " ")))
}

new_clue_book <- function(lines, index) {
  book <- new.env(parent = emptyenv())
  book$entries <- book$added <- 0L
  book$invalid <- book$unknown <- list()
  book$clues <- lapply(index$words, function(word) list())
  for (i in seq_along(lines)) {
    line <- lines[i]
    if (ignored(line)) next
    book$entries <- book$entries + 1L
    reason <- clue_line_error(line)
    if (nzchar(reason)) {
      book$invalid[[length(book$invalid) + 1L]] <- list(line = i, reason = reason)
      next
    }
    split <- regexpr("|", line, fixed = TRUE)[1L]
    word <- substr(line, 1L, split - 1L)
    text <- substring(line, split + 1L)
    id <- word_id(index, word)
    if (!id) {
      book$unknown[[length(book$unknown) + 1L]] <- list(line = i, word = word)
    } else {
      number <- length(book$clues[[id]]) + 1L
      book$clues[[id]][[number]] <- list(text = text, uses = 0L)
      book$added <- book$added + 1L
    }
  }
  book
}

choose_clue <- function(book, id) {
  clues <- book$clues[[id]]
  if (!length(clues)) return("")
  uses <- vapply(clues, function(clue) clue$uses, integer(1))
  chosen <- which.min(uses)
  book$clues[[id]][[chosen]]$uses <- clues[[chosen]]$uses + 1L
  clues[[chosen]]$text
}

clue_report <- function(book, index) {
  word_count <- sum(lengths(book$clues) > 0L)
  lines <- sprintf("CLUES entries=%d valid=%d invalid=%d unknown=%d words=%d", book$entries, book$added, length(book$invalid), length(book$unknown), word_count)
  for (issue in book$invalid) lines <- c(lines, paste("clue_invalid", issue$line, issue$reason))
  for (issue in book$unknown) lines <- c(lines, paste("clue_unknown", issue$line, issue$word))
  uses <- unlist(lapply(book$clues, function(clues) vapply(clues, function(clue) clue$uses, integer(1))), use.names = FALSE)
  used <- sum(uses > 0L)
  repeated <- sum(uses >= 2L)
  lines <- c(lines, sprintf("CLUE_USE used=%d unused=%d repeated=%d", used, book$added - used, repeated))
  for (id in order(index$words, method = "radix")) {
    for (number in seq_along(book$clues[[id]])) {
      clue <- book$clues[[id]][[number]]
      if (clue$uses >= 2L) lines <- c(lines, sprintf("repeated %s clue=%d uses=%d", index$words[id], number, clue$uses))
    }
  }
  lines
}

split_blocks <- function(lines) {
  blocks <- list()
  current <- NULL
  for (line in lines) {
    if (is.null(current)) {
      if (startsWith(line, "TEMPLATE ")) current <- list(name = substring(line, 10L), options = character(), rows = character())
    } else if (line == "END") {
      blocks[[length(blocks) + 1L]] <- current
      current <- NULL
    } else if (grepl(" ", line, fixed = TRUE)) {
      current$options <- c(current$options, line)
    } else {
      current$rows <- c(current$rows, line)
    }
  }
  blocks
}

valid_name <- function(name) nzchar(name) && nchar(name) <= 20L && grepl("^[a-z0-9_]+$", name)
valid_row <- function(row, width) nchar(row) >= 3L && nchar(row) <= 15L && nchar(row) == width && grepl("^[.#A-Z]+$", row)

prepare <- function(block, defaults, names, index) {
  invalid <- function(reason) list(prepared = NULL, error = reason)
  if (!valid_name(block$name)) return(invalid("bad name"))
  if (block$name %in% names) return(invalid("duplicate name"))
  settings <- defaults
  seen <- themes <- character()
  for (i in seq_along(block$options)) {
    line <- block$options[i]
    split <- regexpr(" ", line, fixed = TRUE)[1L]
    key <- substr(line, 1L, split - 1L)
    value <- substring(line, split + 1L)
    valid <- FALSE
    if (key == "theme") {
      if (valid_word(value) && !(value %in% themes)) {
        themes <- c(themes, value)
        valid <- TRUE
      }
    } else if (!(key %in% seen)) {
      if (key == "node_budget" && valid_integer(value, 1L, 100000L)) {
        settings$budget <- as.integer(value)
        valid <- TRUE
      } else if (key == "min_score" && valid_integer(value, 1L, 100L)) {
        settings$minimum <- as.integer(value)
        valid <- TRUE
      } else if (key == "symmetry" && value %in% c("rot180", "mirror", "none")) {
        settings$symmetry <- value
        valid <- TRUE
      }
    }
    if (!valid) return(invalid(paste("bad option", i)))
    seen <- c(seen, key)
  }
  if (length(block$rows) < 3L || length(block$rows) > 15L) return(invalid("bad height"))
  width <- nchar(block$rows[1L])
  for (i in seq_along(block$rows)) if (!valid_row(block$rows[i], width)) return(invalid(paste("bad row", i)))
  grid <- new_grid(block$rows)
  if (settings$symmetry != "none") {
    cell <- asymmetric_cell(grid, settings$symmetry)
    if (cell) return(invalid(paste("asymmetric at", location_text(grid, cell))))
  }
  components <- component_count(grid)
  if (components != 1L) return(invalid(paste0("disconnected components=", components)))
  reason <- short_run_error(grid)
  if (nzchar(reason)) return(invalid(reason))
  layout <- new_layout(grid)
  orphan <- orphan_cell(layout)
  if (orphan) return(invalid(paste("orphan cell", location_text(grid, orphan))))
  initial <- new_grid_state(grid$cells, length(layout$slots), length(index$words))
  theme_slots <- rep(FALSE, length(layout$slots))
  for (i in seq_along(themes)) {
    theme <- themes[i]
    id <- word_id(index, theme)
    if (!id) return(invalid(paste("unknown theme", i)))
    chosen <- 0L
    for (slot in layout$slots) {
      if (!initial$words[slot$index] && slot$length == nchar(theme) && matches(index$letters[[id]], slot_pattern(initial, slot))) {
        chosen <- slot$index
        break
      }
    }
    if (!chosen) return(invalid(paste("theme", i, "does not fit")))
    initial <- assign_word(initial, layout$slots[[chosen]], id, index)$state
    theme_slots[chosen] <- TRUE
  }
  list(prepared = list(settings = settings, layout = layout, initial = initial, theme_slots = theme_slots), error = "")
}

new_completed <- function(prepared, index, clues) {
  attempts <- list()
  minimum <- prepared$settings$minimum
  repeat {
    attempt <- new_attempt(prepared$layout, index, prepared$initial, minimum, prepared$settings$budget)
    run_attempt(attempt)
    attempts[[length(attempts) + 1L]] <- attempt
    if (attempt$outcome == "filled" || prepared$settings$relax < 1L || minimum <= 1L) break
    minimum <- max(minimum - prepared$settings$relax, 1L)
  }
  state <- copy_state(final_state(attempt))
  chosen <- rep("", length(prepared$layout$slots))
  for (across in c(TRUE, FALSE)) {
    for (slot in prepared$layout$slots) {
      if (slot$across == across && state$words[slot$index]) chosen[slot$index] <- choose_clue(clues, state$words[slot$index])
    }
  }
  list(prepared = prepared, attempts = attempts, state = state, chosen = chosen)
}

last_attempt <- function(result) tail(result$attempts, 1L)[[1L]]
is_filled <- function(result) last_attempt(result)$outcome == "filled"
total_score <- function(result, index) sum(index$scores[result$state$words[result$state$words > 0L]])
slot_entry <- function(result, slot, index) {
  id <- result$state$words[slot$index]
  paste(slot$label, index$words[id], index$scores[id], sep = ":")
}

clue_paragraph <- function(name, result, index) {
  lines <- paste("TEMPLATE", name)
  clued <- missing <- unfilled <- 0L
  for (across in c(TRUE, FALSE)) {
    group <- Filter(function(slot) slot$across == across, result$prepared$layout$slots)
    if (length(group)) lines <- c(lines, if (across) "ACROSS" else "DOWN")
    for (slot in group) {
      id <- result$state$words[slot$index]
      if (!id) {
        unfilled <- unfilled + 1L
        lines <- c(lines, list_line(slot, "(unfilled)", paste(slot_pattern(result$state, slot), collapse = ""), "-", FALSE))
      } else {
        clue <- result$chosen[slot$index]
        if (!nzchar(clue)) {
          missing <- missing + 1L
          clue <- "(no clue)"
        } else {
          clued <- clued + 1L
        }
        lines <- c(lines, list_line(slot, clue, index$words[id], index$scores[id], result$prepared$theme_slots[slot$index]))
      }
    }
  }
  c(lines, sprintf("clued=%d missing=%d unfilled=%d", clued, missing, unfilled))
}

stats_paragraph <- function(name, result, index) {
  p <- result$prepared
  layout <- p$layout
  grid <- layout$grid
  slots <- layout$slots
  state <- result$state
  final <- last_attempt(result)
  whites <- white_cells(grid)
  blacks <- length(grid$cells) - length(whites)
  givens <- sum(grid$cells[whites] != ".")
  holding <- c("rot180", "mirror")
  holding <- holding[vapply(holding, function(symmetry) !asymmetric_cell(grid, symmetry), logical(1))]
  symmetry <- if (length(holding)) paste(holding, collapse = ",") else "none"
  sizes <- vapply(slots, function(slot) slot$length, integer(1))
  lengths <- sort(unique(sizes), method = "radix")
  across <- sum(vapply(slots, function(slot) slot$across, logical(1)))
  unchecked <- sum(vapply(whites, function(cell) owner_count(layout, cell) == 1L, logical(1)))
  length_text <- paste(paste0(lengths, ":", vapply(lengths, function(size) sum(sizes == size), integer(1))), collapse = ",")
  lines <- c(paste("TEMPLATE", name),
    sprintf("grid size=%dx%d blocks=%d white=%d density=%s givens=%d required=%s symmetry=%s", grid$width, grid$height, blacks, length(whites), decimal_text(100 * blacks, length(grid$cells), 1L), givens, p$settings$symmetry, symmetry),
    sprintf("slots across=%d down=%d total=%d lengths=%s avg_length=%s longest=%d unchecked=%d", across, length(slots) - across, length(slots), length_text, decimal_text(sum(sizes), length(slots), 2L), max(sizes), unchecked))
  themes <- vapply(Filter(function(slot) p$theme_slots[slot$index], slots), function(slot) slot_entry(result, slot, index), character(1))
  if (length(themes)) lines <- c(lines, paste("themes", paste(themes, collapse = " ")))
  supply <- vapply(lengths, function(size) paste0(size, ":", sum(index$scores[index$by_length[[size]]] >= p$settings$minimum)), character(1))
  lines <- c(lines, paste("coverage", paste(supply, collapse = " ")))
  non_theme <- which(!p$theme_slots)
  tight_counts <- vapply(non_theme, function(i) length(candidates(index, slot_pattern(p$initial, slots[[i]]), p$settings$minimum, p$initial$used)), integer(1))
  tight <- head(order(tight_counts, non_theme, method = "radix"), 3L)
  tight_text <- vapply(tight, function(i) paste0(slots[[non_theme[i]]]$label, ":", tight_counts[i]), character(1))
  lines <- c(lines, paste("tightest", joined(tight_text, " ")))
  for (i in seq_along(result$attempts)) {
    attempt <- result$attempts[[i]]
    lines <- c(lines, sprintf("attempt %d min_score=%d budget=%d outcome=%s nodes=%d backtracks=%d prunes=%d dead_ends=%d max_depth=%d", i, attempt$minimum, attempt$budget, attempt$outcome, attempt$nodes, attempt$backtracks, attempt$prunes, attempt$dead_ends, attempt$max_depth))
  }
  lines <- c(lines, paste("trace", joined(final$trace, " ")))
  failed <- which(final$failures > 0L)
  hot <- head(failed[order(-final$failures[failed], failed, method = "radix")], 3L)
  hot_text <- vapply(hot, function(i) paste0(slots[[i]]$label, ":", final$failures[i]), character(1))
  lines <- c(lines, paste("hotspots", joined(hot_text, " ")))
  if (is_filled(result)) {
    order_text <- vapply(final$sequence, function(i) slots[[i]]$label, character(1))
    lines <- c(lines, paste("order", joined(order_text, " ")))
    scores <- index$scores[state$words]
    weakest <- which.min(scores)
    weak <- vapply(which(scores < p$settings$weak), function(i) slot_entry(result, slots[[i]], index), character(1))
    total <- total_score(result, index)
    lines <- c(lines, sprintf("quality total=%d average=%s weakest=%s weak=%s", total, decimal_text(total, length(slots), 2L), slot_entry(result, slots[[weakest]], index), joined(weak, ",")))
    letters <- state$letters[whites]
    present <- unique(letters)
    missing <- paste(LETTERS[!(LETTERS %in% present)], collapse = "")
    points <- sum(letter_points[match(letters, LETTERS)])
    worst <- 0L
    worst_sum <- 0L
    for (cell in whites) {
      a <- layout$across_slot[cell]
      d <- layout$down_slot[cell]
      if (!a || !d) next
      combined <- index$scores[state$words[a]] + index$scores[state$words[d]]
      if (!worst || combined < worst_sum) {
        worst <- cell
        worst_sum <- combined
      }
    }
    crossing <- "-"
    if (worst) {
      a <- layout$across_slot[worst]
      d <- layout$down_slot[worst]
      crossing <- paste0(location_text(grid, worst), " ", slots[[a]]$label, ":", index$words[state$words[a]], "+", slots[[d]]$label, ":", index$words[state$words[d]], "=", worst_sum)
    }
    lines <- c(lines, sprintf("letters distinct=%d pangram=%s missing=%s scrabble=%s worst_crossing=%s", length(present), if (!nzchar(missing)) "yes" else "no", if (nzchar(missing)) missing else "-", decimal_text(points, length(whites), 2L), crossing))
  } else {
    assigned <- sum(state$words > 0L)
    lettered <- sum(state$letters[whites] != ".")
    blocked <- vapply(Filter(function(slot) !state$words[slot$index] && !length(candidates(index, slot_pattern(state, slot), final$minimum, state$used)), slots), function(slot) slot$label, character(1))
    lines <- c(lines, sprintf("partial assigned=%d/%d letters=%d/%d blocked=%s", assigned, length(slots), lettered, length(whites), joined(blocked, ",")))
  }
  lines
}

grid_paragraph <- function(template) {
  lines <- paste("TEMPLATE", template$name)
  if (nzchar(template$error)) return(c(lines, paste("error", template$error)))
  result <- template$completed
  final <- last_attempt(result)
  c(lines, sprintf("outcome=%s attempts=%d min_score=%d", final$outcome, length(result$attempts), final$minimum), grid_lines(result$prepared$layout$grid, result$state$letters), "numbers", number_lines(result$prepared$layout))
}

ascii_less <- function(first, second) first != second && order(c(first, second), method = "radix")[1L] == 1L

overall_paragraphs <- function(templates, index) {
  valid <- Filter(function(template) !nzchar(template$error), templates)
  filled <- Filter(function(template) is_filled(template$completed), valid)
  ranked <- list()
  for (candidate in filled) {
    total <- total_score(candidate$completed, index)
    entries <- length(candidate$completed$prepared$layout$slots)
    position <- length(ranked) + 1L
    ranked[[position]] <- candidate
    while (position > 1L) {
      previous <- ranked[[position - 1L]]
      left <- total * length(previous$completed$prepared$layout$slots)
      right <- total_score(previous$completed, index) * entries
      if (left < right || (left == right && !ascii_less(candidate$name, previous$name))) break
      ranked[[position]] <- previous
      position <- position - 1L
    }
    ranked[[position]] <- candidate
  }
  ranking <- "RANKING"
  for (i in seq_along(ranked)) {
    template <- ranked[[i]]
    total <- total_score(template$completed, index)
    entries <- length(template$completed$prepared$layout$slots)
    ranking <- c(ranking, sprintf("rank %d %s average=%s total=%d entries=%d", i, template$name, decimal_text(total, entries, 2L), total, entries))
  }
  appearances <- lapply(index$words, function(word) character())
  for (template in filled) {
    for (id in template$completed$state$words) appearances[[id]] <- c(appearances[[id]], template$name)
  }
  reused <- which(lengths(appearances) >= 2L)
  reused <- reused[order(-lengths(appearances)[reused], index$words[reused], method = "radix")]
  reuse <- "REUSE"
  for (id in reused) reuse <- c(reuse, paste("reused", index$words[id], length(appearances[[id]]), paste(appearances[[id]], collapse = ",")))
  attempts <- sum(vapply(valid, function(template) length(template$completed$attempts), integer(1)))
  nodes <- sum(vapply(valid, function(template) sum(vapply(template$completed$attempts, function(attempt) attempt$nodes, integer(1))), integer(1)))
  unfillable <- sum(vapply(valid, function(template) last_attempt(template$completed)$outcome == "unfillable", logical(1)))
  budget <- sum(vapply(valid, function(template) last_attempt(template$completed)$outcome == "budget", logical(1)))
  summary <- sprintf("SUMMARY templates=%d invalid=%d filled=%d unfillable=%d budget=%d attempts=%d nodes=%d", length(templates), length(templates) - length(valid), length(filled), unfillable, budget, attempts, nodes)
  list(ranking, reuse, summary)
}

main <- function() {
  settings <- read_settings(read_input_lines("params.txt"))
  word_list <- new_word_list(read_input_lines("words.txt"))
  index <- word_list$index
  clues <- new_clue_book(read_input_lines("clues.txt"), index)
  templates <- list()
  names <- character()
  for (block in split_blocks(read_input_lines("templates.txt"))) {
    checked <- prepare(block, settings, names, index)
    completed <- if (!nzchar(checked$error)) new_completed(checked$prepared, index, clues) else NULL
    templates[[length(templates) + 1L]] <- list(name = block$name, error = checked$error, completed = completed)
    names <- c(names, block$name)
  }
  valid <- Filter(function(template) !nzchar(template$error), templates)
  grids <- lapply(templates, grid_paragraph)
  clue_lines <- lapply(valid, function(template) clue_paragraph(template$name, template$completed, index))
  stats <- lapply(valid, function(template) stats_paragraph(template$name, template$completed, index))
  stats <- c(stats, overall_paragraphs(templates, index))
  dir.create("output", showWarnings = FALSE, recursive = TRUE)
  write_paragraphs("grid.txt", grids)
  write_paragraphs("clues.txt", clue_lines)
  write_paragraphs("search_stats.txt", stats)
  write_lines("wordlist.txt", c(word_report(word_list), clue_report(clues, index)))
}

main()
