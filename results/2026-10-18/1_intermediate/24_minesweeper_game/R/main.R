suppressPackageStartupMessages(library(gmp))

arity <- c(NEW = 4L, PRESET = 2L, LAYOUT = 2L, SAFETY = 1L, RESTART = 0L,
           REVEAL = 2L, FLAG = 2L, UNFLAG = 2L, QUESTION = 2L, CHORD = 2L,
           UNDO = 0L, SHOW = 0L, STATUS = 0L, CELL = 2L, HISTORY = 1L,
           REPLAY = 1L, HINT = 0L, AUTO = 0L, ANALYZE = 0L, PROB = 2L,
           FRONTIER = 0L, SOLVE = 0L, BOARDINFO = 0L, STATS = 0L)
cell_commands <- c("REVEAL", "FLAG", "UNFLAG", "QUESTION", "CHORD", "CELL", "PROB")
active_commands <- c("REVEAL", "FLAG", "UNFLAG", "QUESTION", "CHORD", "UNDO",
                     "HINT", "AUTO", "ANALYZE", "PROB", "FRONTIER", "SOLVE")
undo_commands <- c("REVEAL", "FLAG", "UNFLAG", "QUESTION", "CHORD", "AUTO", "SOLVE")

emit <- function(...) cat(paste(..., sep = " "), "\n", sep = "")
fail <- function(reason) {
  stop(structure(list(message = reason, call = NULL),
                 class = c("command_error", "error", "condition")))
}

number_word <- function(text) {
  if (!grepl("^(0|[1-9][0-9]{0,9})$", text, perl = TRUE)) fail("bad arguments")
  as.numeric(text)
}

fraction <- function(numerator, denominator) {
  a <- numerator
  b <- denominator
  while (b != 0L) {
    rest <- a %% b
    a <- b
    b <- rest
  }
  paste0(numerator %/% a, "/", denominator %/% a)
}

new_board <- function(width, height, mine_count, seed) {
  size <- width * height
  neighbors <- lapply(seq_len(size), function(cell) {
    column <- (cell - 1L) %% width
    row <- (cell - 1L) %/% width
    result <- integer()
    for (dy in -1:1) for (dx in -1:1) {
      x <- column + dx
      y <- row + dy
      if ((dx != 0L || dy != 0L) && x >= 0L && x < width && y >= 0L && y < height) {
        result <- c(result, x + width * y + 1L)
      }
    }
    result
  })
  list2env(list(width = width, height = height, mine_count = mine_count, seed = seed,
                placed = FALSE, mines = rep(FALSE, size), numbers = integer(size),
                revealed = rep(FALSE, size), marks = integer(size), neighbors = neighbors,
                state = "ready", exploded = 0L, moves = list(), undos = list()), parent = emptyenv())
}

copy_board <- function(board) list2env(as.list(board), parent = emptyenv())
cell_text <- function(board, cell) paste0((cell - 1L) %% board$width, ",", (cell - 1L) %/% board$width)
size_text <- function(board) paste0(board$width, "x", board$height)
remaining_mines <- function(board) board$mine_count - sum(board$marks == 1L)
revealed_count <- function(board) sum(board$revealed)
safe_count <- function(board) board$width * board$height - board$mine_count
is_unknown <- function(board, cells) !board$revealed[cells] & board$marks[cells] != 1L
unknown_cells <- function(board) which(!board$revealed & board$marks != 1L)
finished <- function(board) board$state %in% c("won", "lost")

compute_numbers <- function(board) {
  board$numbers <- vapply(board$neighbors, function(neighbors) sum(board$mines[neighbors]), integer(1L))
}

place_mines <- function(board, first, safety) {
  choices <- seq_along(board$mines)
  if (safety == "cell") choices <- choices[choices != first]
  if (safety == "block") {
    x <- (first - 1L) %% board$width
    y <- (first - 1L) %/% board$width
    choices <- choices[abs((choices - 1L) %% board$width - x) >= 2L |
                       abs((choices - 1L) %/% board$width - y) >= 2L]
  }
  generator <- as.bigz(board$seed)
  for (i in seq_len(board$mine_count)) {
    generator <- (48271L * generator) %% 2147483647L
    index <- as.integer(as.character(generator %% length(choices))) + 1L
    board$mines[choices[index]] <- TRUE
    choices <- choices[-index]
  }
  compute_numbers(board)
  board$placed <- TRUE
  board$state <- "playing"
}

reset_board <- function(board) {
  board$revealed[] <- FALSE
  board$marks[] <- 0L
  board$moves <- list()
  board$undos <- list()
  board$exploded <- 0L
  board$state <- if (board$placed) "playing" else "ready"
}

reveal_cell <- function(board, cell, safety) {
  if (!board$placed) place_mines(board, cell, safety)
  if (board$mines[cell]) {
    board$state <- "lost"
    board$exploded <- cell
    return(0L)
  }
  board$revealed[cell] <- TRUE
  board$marks[cell] <- 0L
  queue <- integer(length(board$mines))
  queue[1L] <- cell
  head <- 1L
  tail <- 1L
  while (head <= tail) {
    current <- queue[head]
    head <- head + 1L
    if (board$numbers[current] == 0L) for (neighbor in board$neighbors[[current]]) {
      if (is_unknown(board, neighbor)) {
        board$revealed[neighbor] <- TRUE
        board$marks[neighbor] <- 0L
        tail <- tail + 1L
        queue[tail] <- neighbor
      }
    }
  }
  tail
}

chord_cells <- function(board, cell, safety) {
  opened <- 0L
  for (neighbor in board$neighbors[[cell]]) if (is_unknown(board, neighbor)) {
    opened <- opened + reveal_cell(board, neighbor, safety)
    if (board$state == "lost") break
  }
  opened
}

win_check <- function(board) {
  if (board$state == "playing" && revealed_count(board) == safe_count(board)) {
    board$state <- "won"
    board$marks[board$mines] <- 1L
  }
}

show_board <- function(board) {
  symbols <- c("#", "F", "?")[board$marks + 1L]
  symbols[board$revealed] <- ifelse(board$numbers[board$revealed] == 0L, ".", board$numbers[board$revealed])
  if (board$state == "lost") {
    symbols[board$mines] <- "*"
    symbols[board$marks == 1L] <- ifelse(board$mines[board$marks == 1L], "F", "X")
    symbols[board$exploded] <- "!"
  }
  for (row in seq_len(board$height)) {
    cells <- (row - 1L) * board$width + seq_len(board$width)
    emit(paste(symbols[cells], collapse = ""))
  }
}

finish_output <- function(board) {
  if (board$state == "lost") {
    emit("boom", cell_text(board, board$exploded))
    show_board(board)
  } else if (board$state == "won") emit("win moves", length(board$moves))
}

record_move <- function(board, kind, cell) {
  board$moves[[length(board$moves) + 1L]] <- list(kind = kind, cell = cell)
}

constraints <- function(board) {
  result <- list()
  for (cell in which(board$revealed & board$numbers > 0L)) {
    neighbors <- board$neighbors[[cell]]
    unknown <- neighbors[is_unknown(board, neighbors)]
    if (length(unknown)) {
      result[[length(result) + 1L]] <- list(cell = cell, unknown = unknown,
        remaining = board$numbers[cell] - sum(board$marks[neighbors] == 1L))
    }
  }
  result
}

deduction <- function(board) {
  known <- constraints(board)
  safe <- mines <- rep(NA_character_, length(board$mines))
  add <- function(reasons, cells, reason) {
    reasons[cells[is.na(reasons[cells])]] <- reason
    reasons
  }
  for (clue in known) if (clue$remaining == 0L) {
    safe <- add(safe, clue$unknown, paste("single", cell_text(board, clue$cell)))
  }
  if (any(!is.na(safe))) return(list(safe = safe, mines = mines))
  for (clue in known) if (clue$remaining == length(clue$unknown)) {
    mines <- add(mines, clue$unknown, paste("single", cell_text(board, clue$cell)))
  }
  if (any(!is.na(mines))) return(list(safe = safe, mines = mines))
  for (left in known) for (right in known) {
    if (length(left$unknown) >= length(right$unknown) || !all(left$unknown %in% right$unknown)) next
    difference <- right$unknown[!right$unknown %in% left$unknown]
    needed <- right$remaining - left$remaining
    reason <- paste("subset", cell_text(board, left$cell), cell_text(board, right$cell))
    if (needed == 0L) safe <- add(safe, difference, reason)
    else if (needed == length(difference)) mines <- add(mines, difference, reason)
  }
  if (!any(!is.na(safe)) && !any(!is.na(mines)) && board$state == "playing" && remaining_mines(board) == 0L) {
    safe <- add(safe, unknown_cells(board), "count")
  }
  list(safe = safe, mines = mines)
}

auto_play <- function(board, safety) {
  totals <- c(rounds = 0L, flagged = 0L, opened = 0L)
  while (board$state == "playing") {
    found <- deduction(board)
    safe <- which(!is.na(found$safe))
    mines <- which(!is.na(found$mines))
    if (!length(safe) && !length(mines)) break
    totals["rounds"] <- totals["rounds"] + 1L
    for (cell in safe) if (!board$revealed[cell]) {
      record_move(board, "auto-reveal", cell)
      totals["opened"] <- totals["opened"] + reveal_cell(board, cell, safety)
      win_check(board)
      if (finished(board)) return(totals)
    }
    for (cell in mines) if (is_unknown(board, cell)) {
      board$marks[cell] <- 1L
      totals["flagged"] <- totals["flagged"] + 1L
      record_move(board, "auto-flag", cell)
    }
  }
  totals
}

count_component <- function(cells, clues) {
  local_sets <- lapply(clues, function(clue) match(clue$unknown, cells))
  required <- vapply(clues, function(clue) clue$remaining, integer(1L))
  touched <- lapply(seq_along(cells), function(cell) which(vapply(local_sets, function(set) cell %in% set, logical(1L))))
  order <- order(-lengths(touched), seq_along(cells), method = "radix")
  left <- lengths(local_sets)
  assigned <- integer(length(clues))
  choice <- hits <- integer(length(cells))
  configs <- 0L
  minimum <- length(cells)
  maximum <- 0L
  search <- function(depth, total) {
    if (depth > length(cells)) {
      configs <<- configs + 1L
      hits <<- hits + choice
      minimum <<- min(minimum, total)
      maximum <<- max(maximum, total)
      return(invisible(NULL))
    }
    position <- order[depth]
    involved <- touched[[position]]
    left[involved] <<- left[involved] - 1L
    for (value in 0:1) {
      choice[position] <<- value
      assigned[involved] <<- assigned[involved] + value
      if (all(assigned[involved] <= required[involved] & assigned[involved] + left[involved] >= required[involved])) {
        search(depth + 1L, total + value)
      }
      assigned[involved] <<- assigned[involved] - value
    }
    left[involved] <<- left[involved] + 1L
  }
  if (all(required >= 0L & required <= left)) search(1L, 0L)
  list(cells = cells, configs = configs, hits = hits, minimum = minimum, maximum = maximum)
}

frontier <- function(board, target = 0L) {
  known <- constraints(board)
  incident <- vector("list", length(board$mines))
  for (index in seq_along(known)) for (cell in known[[index]]$unknown) {
    incident[[cell]] <- c(incident[[cell]], index)
  }
  mask <- lengths(incident) > 0L
  result <- list(mask = mask, components = list())
  if (target != 0L && !mask[target]) return(result)
  visited <- rep(FALSE, length(mask))
  expanded <- rep(FALSE, length(known))
  for (root in which(mask)) {
    if (visited[root]) next
    queue <- root
    visited[root] <- TRUE
    clue_ids <- integer()
    head <- 1L
    while (head <= length(queue)) {
      cell <- queue[head]
      head <- head + 1L
      for (index in incident[[cell]]) {
        if (expanded[index]) next
        expanded[index] <- TRUE
        clue_ids <- c(clue_ids, index)
        added <- known[[index]]$unknown[!visited[known[[index]]$unknown]]
        visited[added] <- TRUE
        queue <- c(queue, added)
      }
    }
    cells <- sort(queue, method = "radix")
    if (target == 0L || target %in% cells) {
      result$components[[length(result$components) + 1L]] <- count_component(cells, known[clue_ids])
      if (target != 0L) break
    }
  }
  result
}

guess_cell <- function(board) {
  boundary <- frontier(board)
  numerator <- integer(length(board$mines))
  denominator <- integer(length(board$mines))
  unknown <- unknown_cells(board)
  outside <- unknown[!boundary$mask[unknown]]
  numerator[outside] <- max(remaining_mines(board), 0L)
  denominator[outside] <- length(unknown)
  for (component in boundary$components) if (component$configs > 0L) {
    numerator[component$cells] <- component$hits
    denominator[component$cells] <- component$configs
  }
  chosen <- 0L
  for (cell in which(denominator > 0L)) {
    if (chosen == 0L || numerator[cell] * denominator[chosen] < numerator[chosen] * denominator[cell]) chosen <- cell
  }
  chosen
}

solve_board <- function(board, safety) {
  totals <- c(guesses = 0L, rounds = 0L, flagged = 0L, opened = 0L)
  repeat {
    totals[c("rounds", "flagged", "opened")] <- totals[c("rounds", "flagged", "opened")] + auto_play(board, safety)
    if (finished(board)) break
    cell <- guess_cell(board)
    if (cell == 0L) break
    totals["guesses"] <- totals["guesses"] + 1L
    record_move(board, "guess", cell)
    totals["opened"] <- totals["opened"] + reveal_cell(board, cell, safety)
    win_check(board)
    if (finished(board)) break
  }
  totals
}

replay_board <- function(board, count, safety) {
  replay <- copy_board(board)
  reset_board(replay)
  for (i in seq_len(count)) {
    move <- board$moves[[i]]
    cell <- move$cell
    if (move$kind %in% c("reveal", "auto-reveal", "guess")) reveal_cell(replay, cell, safety)
    else if (move$kind == "chord") chord_cells(replay, cell, safety)
    else if (move$kind %in% c("flag", "auto-flag")) replay$marks[cell] <- 1L
    else if (move$kind == "unflag") replay$marks[cell] <- 0L
    else replay$marks[cell] <- if (replay$marks[cell] == 2L) 0L else 2L
    win_check(replay)
  }
  replay
}

board_info <- function(board) {
  blank <- !board$mines & board$numbers == 0L
  visited <- covered <- rep(FALSE, length(blank))
  openings <- largest <- 0L
  for (root in which(blank)) {
    if (visited[root]) next
    openings <- openings + 1L
    queue <- root
    visited[root] <- TRUE
    coverage <- rep(FALSE, length(blank))
    coverage[root] <- TRUE
    head <- 1L
    while (head <= length(queue)) {
      cell <- queue[head]
      head <- head + 1L
      neighbors <- board$neighbors[[cell]]
      coverage[neighbors] <- TRUE
      added <- neighbors[blank[neighbors] & !visited[neighbors]]
      visited[added] <- TRUE
      queue <- c(queue, added)
    }
    covered <- covered | coverage
    largest <- max(largest, sum(coverage))
  }
  emit("3bv", openings + sum(!board$mines & !covered), "openings", openings,
       "largest", largest, "mines", board$mine_count, "safe", safe_count(board))
}

update_statistics <- function(app, board) {
  stats <- app$stats
  stats$played <- stats$played + 1L
  if (board$state == "won") {
    stats$won <- stats$won + 1L
    stats$streak <- stats$streak + 1L
    stats$best <- max(stats$best, stats$streak)
    stats$fastest <- if (is.null(stats$fastest)) length(board$moves) else min(stats$fastest, length(board$moves))
  } else {
    stats$lost <- stats$lost + 1L
    stats$streak <- 0L
  }
  app$stats <- stats
}

layout_command <- function(app, width, height, rows) {
  for (i in seq_along(rows)) {
    if (nchar(rows[i], type = "bytes") != width || !grepl("^[*.]+$", rows[i])) fail(paste("bad row", i))
  }
  mines <- unlist(strsplit(rows, "", fixed = TRUE), use.names = FALSE) == "*"
  count <- sum(mines)
  if (count == 0L || count == width * height) fail(paste("bad mine count", count))
  board <- new_board(width, height, count, 0L)
  board$mines <- mines
  compute_numbers(board)
  board$placed <- TRUE
  board$state <- "playing"
  app$board <- board
  emit("layout", size_text(board), "mines", count)
}

execute <- function(app, words) {
  command <- words[1L]
  arguments <- words[-1L]
  if (!command %in% names(arity)) fail(paste("unknown command", command))
  if (length(arguments) != arity[[command]]) fail("bad arguments")
  values <- numeric()
  if (command == "PRESET") {
    if (!arguments[1L] %in% c("beginner", "intermediate", "expert")) fail("bad arguments")
    values <- number_word(arguments[2L])
  } else if (command == "SAFETY") {
    if (!arguments[1L] %in% c("block", "cell", "none")) fail("bad arguments")
  } else if (length(arguments)) values <- vapply(arguments, number_word, numeric(1L))
  if (command %in% c("NEW", "PRESET")) {
    if (command == "NEW") {
      width <- values[1L]
      height <- values[2L]
      mines <- values[3L]
      seed <- values[4L]
    } else {
      preset <- switch(arguments[1L], beginner = c(9L, 9L, 10L),
                       intermediate = c(16L, 16L, 40L), expert = c(30L, 16L, 99L))
      width <- preset[1L]
      height <- preset[2L]
      mines <- preset[3L]
      seed <- values[1L]
    }
    if (width < 1L || width > 30L || height < 1L || height > 30L ||
        mines < 1L || mines > width * height - 9L || seed < 1L || seed > 2147483646L) fail("bad value")
    app$board <- new_board(as.integer(width), as.integer(height), as.integer(mines), as.integer(seed))
    emit("new", size_text(app$board), "mines", mines)
    return(invisible(NULL))
  }
  if (command == "HISTORY" && values[1L] == 0) fail("bad value")
  if (command == "SAFETY") {
    app$safety <- arguments[1L]
    emit("safety", app$safety)
    return(invisible(NULL))
  }
  if (command == "STATS") {
    stats <- app$stats
    rate <- if (stats$played == 0L) "-" else paste0((100L * stats$won) %/% stats$played, "%")
    fastest <- if (is.null(stats$fastest)) "-" else stats$fastest
    emit("stats played", stats$played, "won", stats$won, "lost", stats$lost, "rate", rate,
         "streak", stats$streak, "best", stats$best, "fastest", fastest)
    return(invisible(NULL))
  }
  board <- app$board
  if (is.null(board)) fail("no game")
  cell <- 0L
  if (command %in% cell_commands) {
    if (values[1L] >= board$width || values[2L] >= board$height) fail("out of range")
    cell <- as.integer(values[1L] + board$width * values[2L]) + 1L
  }
  if (command %in% active_commands && finished(board)) fail("game over")
  if (command %in% c("ANALYZE", "BOARDINFO") && !board$placed) fail("not started")
  before <- if (command %in% undo_commands) {
    list(kind = tolower(command), revealed = board$revealed, marks = board$marks, moves = board$moves)
  } else NULL
  switch(command,
    RESTART = {
      reset_board(board)
      emit("restart", size_text(board), "mines", board$mine_count)
    },
    REVEAL = {
      if (board$revealed[cell]) fail("already revealed")
      if (board$marks[cell] == 1L) fail("flagged")
      record_move(board, "reveal", cell)
      opened <- reveal_cell(board, cell, app$safety)
      if (board$state != "lost") {
        emit("revealed", opened)
        win_check(board)
      }
      finish_output(board)
    },
    FLAG = {
      if (board$revealed[cell]) fail("already revealed")
      if (board$marks[cell] == 1L) fail("already flagged")
      board$marks[cell] <- 1L
      record_move(board, "flag", cell)
      emit("flagged", cell_text(board, cell), "left", remaining_mines(board))
    },
    UNFLAG = {
      if (board$revealed[cell]) fail("already revealed")
      if (board$marks[cell] != 1L) fail("not flagged")
      board$marks[cell] <- 0L
      record_move(board, "unflag", cell)
      emit("unflagged", cell_text(board, cell), "left", remaining_mines(board))
    },
    QUESTION = {
      if (board$revealed[cell]) fail("already revealed")
      record_move(board, "question", cell)
      board$marks[cell] <- if (board$marks[cell] == 2L) 0L else 2L
      emit(if (board$marks[cell] == 0L) "unmarked" else "questioned", cell_text(board, cell), "left", remaining_mines(board))
    },
    CHORD = {
      if (!board$revealed[cell]) fail("not revealed")
      if (board$numbers[cell] == 0L) fail("no number")
      neighbors <- board$neighbors[[cell]]
      flags <- sum(board$marks[neighbors] == 1L)
      if (flags != board$numbers[cell]) fail(paste("flags", flags, "of", board$numbers[cell]))
      if (!any(is_unknown(board, neighbors))) fail("nothing to reveal")
      record_move(board, "chord", cell)
      opened <- chord_cells(board, cell, app$safety)
      if (board$state != "lost") {
        emit("chorded", opened)
        win_check(board)
      }
      finish_output(board)
    },
    UNDO = {
      count <- length(board$undos)
      if (count == 0L) fail("nothing to undo")
      saved <- board$undos[[count]]
      board$undos <- board$undos[-count]
      board$revealed <- saved$revealed
      board$marks <- saved$marks
      board$moves <- saved$moves
      emit("undo", saved$kind, "moves", length(board$moves))
    },
    SHOW = show_board(board),
    STATUS = emit("status", board$state, "left", remaining_mines(board), "moves", length(board$moves),
                  "revealed", paste0(revealed_count(board), "/", safe_count(board))),
    CELL = {
      neighbors <- board$neighbors[[cell]]
      if (board$revealed[cell]) {
        emit("cell", cell_text(board, cell), "number", board$numbers[cell],
             "flags", sum(board$marks[neighbors] == 1L), "unknown", sum(is_unknown(board, neighbors)))
      } else {
        emit("cell", cell_text(board, cell), "hidden mark", c("none", "flag", "question")[board$marks[cell] + 1L],
             "open", sum(board$revealed[neighbors]))
      }
    },
    HISTORY = {
      count <- length(board$moves)
      emit("history", count)
      if (count > 0L) for (i in seq.int(max(1L, count - values[1L] + 1L), count)) {
        move <- board$moves[[i]]
        emit(i, move$kind, cell_text(board, move$cell))
      }
    },
    REPLAY = {
      if (values[1L] > length(board$moves)) fail(paste("no move", arguments[1L]))
      emit("replay", paste0(arguments[1L], "/", length(board$moves)))
      show_board(replay_board(board, as.integer(values[1L]), app$safety))
    },
    HINT = {
      found <- deduction(board)
      safe <- which(!is.na(found$safe))
      mines <- which(!is.na(found$mines))
      if (length(safe)) emit("hint safe", cell_text(board, safe[1L]), "by", found$safe[safe[1L]])
      else if (length(mines)) emit("hint mine", cell_text(board, mines[1L]), "by", found$mines[mines[1L]])
      else emit("hint none")
    },
    AUTO = {
      totals <- auto_play(board, app$safety)
      emit("auto rounds", totals["rounds"], "flagged", totals["flagged"], "revealed", totals["opened"])
      finish_output(board)
    },
    ANALYZE = {
      trial <- copy_board(board)
      totals <- auto_play(trial, app$safety)
      if (trial$state == "lost") emit("analyze boom", cell_text(trial, trial$exploded), "rounds", totals["rounds"])
      else if (trial$state == "won") emit("analyze clear rounds", totals["rounds"])
      else emit("analyze stuck rounds", totals["rounds"], "revealed", paste0(revealed_count(trial), "/", safe_count(trial)))
    },
    PROB = {
      if (board$revealed[cell]) fail("already revealed")
      if (board$marks[cell] == 1L) fail("flagged")
      boundary <- frontier(board, cell)
      if (!boundary$mask[cell]) emit("prob", cell_text(board, cell), "unconstrained")
      else {
        component <- boundary$components[[1L]]
        if (component$configs == 0L) emit("prob", cell_text(board, cell), "inconsistent")
        else emit("prob", cell_text(board, cell), fraction(component$hits[match(cell, component$cells)], component$configs),
                  "size", length(component$cells), "configs", component$configs)
      }
    },
    FRONTIER = {
      boundary <- frontier(board)
      emit("frontier", sum(boundary$mask), "components", length(boundary$components))
      for (component in boundary$components) {
        prefix <- paste("component", cell_text(board, component$cells[1L]), "size", length(component$cells))
        if (component$configs == 0L) emit(prefix, "inconsistent")
        else emit(prefix, "configs", component$configs, "min", component$minimum, "max", component$maximum)
      }
    },
    SOLVE = {
      totals <- solve_board(board, app$safety)
      emit("solve guesses", totals["guesses"], "rounds", totals["rounds"], "flagged", totals["flagged"], "revealed", totals["opened"])
      finish_output(board)
    },
    BOARDINFO = board_info(board)
  )
  if (!is.null(before) && length(board$moves) > length(before$moves)) {
    board$undos[[length(board$undos) + 1L]] <- before
    if (finished(board)) update_statistics(app, board)
  }
  invisible(NULL)
}

input <- file("stdin", open = "r")
count <- as.integer(readLines(input, n = 1L))
app <- new.env(parent = emptyenv())
app$board <- NULL
app$safety <- "block"
app$stats <- list(played = 0L, won = 0L, lost = 0L, streak = 0L, best = 0L, fastest = NULL)
for (i in seq_len(count)) {
  words <- strsplit(readLines(input, n = 1L), " ", fixed = TRUE)[[1L]]
  rows <- if (words[1L] == "LAYOUT") readLines(input, n = as.integer(words[3L])) else character()
  tryCatch({
    if (words[1L] == "LAYOUT") layout_command(app, as.integer(words[2L]), as.integer(words[3L]), rows)
    else execute(app, words)
  }, command_error = function(error) emit("error:", conditionMessage(error)))
}
close(input)
