DIRECTIONS <- c("u", "d", "l", "r")
PUSH_LETTERS <- toupper(DIRECTIONS)
DELTAS <- list(u = c(-1, 0), d = c(1, 0), l = c(0, -1), r = c(0, 1))
TURNS <- list(
  ROT90 = c(u = "r", d = "l", l = "u", r = "d"),
  ROT180 = c(u = "d", d = "u", l = "r", r = "l"),
  ROT270 = c(u = "l", d = "r", l = "d", r = "u"),
  FLIPH = c(u = "u", d = "d", l = "r", r = "l"),
  FLIPV = c(u = "d", d = "u", l = "l", r = "r")
)
STEP_LETTERS <- c(DIRECTIONS, PUSH_LETTERS)
LEVEL_CHARACTERS <- c("#", "-", ".", "$", "*", "@", "+")
DIGITS <- as.character(0:9)
MAX_SIDE <- 10
MAX_LIMIT <- 100000
NUMBER_WORD <- "^(0|[1-9][0-9]{0,5})$"
NAME_WORD <- "^[a-z]{1,8}$"
CELL <- c("number", "number")
COMMANDS <- list(
  IMPORT = "text",
  VALID = character(0),
  INFO = character(0),
  SHOW = character(0),
  EXPORT = character(0),
  MOVE = "steps",
  PUSH = c(CELL, "direction"),
  BRING = c(CELL, CELL),
  PATH = CELL,
  UNDO = "number",
  REDO = "number",
  RESET = character(0),
  STATUS = character(0),
  HISTORY = character(0),
  BOXES = character(0),
  REACH = character(0),
  DEADSQUARES = character(0),
  DEADLOCK = character(0),
  BOUND = character(0),
  SAVE = "name",
  RESTORE = "name",
  CHECK = "steps",
  SOLVE = "number",
  HINT = "number",
  PLAY = character(0),
  TRANSFORM = "transform"
)
CELL_COUNTS <- c(PATH = 1, PUSH = 1, BRING = 2)
LEVEL_FREE_COMMANDS <- c("IMPORT", "VALID")

chars <- function(text) {
  strsplit(text, "")[[1]]
}

command_error <- function(message) {
  stop(errorCondition(message, class = "command_error"))
}

step_failure <- function(reason) {
  stop(errorCondition(reason, class = "step_failure"))
}

emit <- function(...) {
  cat(paste(...), "\n", sep = "")
}

decode <- function(text, allowed) {
  pieces <- character(0)
  index <- 1
  while (index <= nchar(text)) {
    start <- index
    while (index <= nchar(text) && substr(text, index, index) %in% DIGITS) {
      index <- index + 1
    }
    count <- substr(text, start, index - 1)
    if (nchar(count) > 2 || startsWith(count, "0") || index > nchar(text)) {
      return(NULL)
    }
    symbol <- substr(text, index, index)
    if (!(symbol %in% allowed)) {
      return(NULL)
    }
    pieces <- c(pieces, strrep(symbol, if (count == "") 1 else as.integer(count)))
    index <- index + 1
  }
  paste(pieces, collapse = "")
}

encode <- function(text) {
  runs <- rle(chars(text))
  counts <- ifelse(runs$lengths > 1, runs$lengths, "")
  paste0(counts, runs$values, collapse = "")
}

step_sequence <- function(word) {
  chars(tolower(decode(word, STEP_LETTERS)))
}

valid_argument <- function(kind, text) {
  switch(kind,
    number = grepl(NUMBER_WORD, text),
    steps = !is.null(decode(text, STEP_LETTERS)),
    direction = text %in% DIRECTIONS,
    name = grepl(NAME_WORD, text),
    transform = text %in% names(TURNS),
    text = TRUE
  )
}

is_push <- function(moves) {
  moves %in% PUSH_LETTERS
}

push_count <- function(moves) {
  sum(is_push(moves))
}

turn_letters <- function(moves, kind) {
  turned <- unname(TURNS[[kind]][tolower(moves)])
  pushes <- is_push(moves)
  turned[pushes] <- toupper(turned[pushes])
  turned
}

move_box <- function(boxes, from, to) {
  sort(replace(boxes, boxes == from, to))
}

counted <- function(label, moves) {
  if (length(moves) == 0) {
    return(paste(label, 0))
  }
  paste(label, length(moves), paste(moves, collapse = ""))
}

split_at_bars <- function(text) {
  bars <- which(chars(text) == "|")
  substring(text, c(1, bars + 1), c(bars - 1, nchar(text)))
}

permutations <- function(items) {
  if (length(items) == 0) {
    return(list(integer(0)))
  }
  result <- list()
  for (item in items) {
    for (tail in permutations(setdiff(items, item))) {
      result[[length(result) + 1]] <- c(item, tail)
    }
  }
  result
}

find_interior <- function(height, width, walls, start) {
  interior <- logical(height * width)
  interior[start] <- TRUE
  stack <- start
  while (length(stack) > 0) {
    cell <- stack[length(stack)]
    stack <- stack[-length(stack)]
    row <- (cell - 1) %/% width
    column <- (cell - 1) %% width
    for (delta in DELTAS) {
      next_row <- row + delta[1]
      next_column <- column + delta[2]
      if (next_row >= 0 && next_row < height && next_column >= 0 && next_column < width) {
        neighbor <- next_row * width + next_column + 1
        if (!walls[neighbor] && !interior[neighbor]) {
          interior[neighbor] <- TRUE
          stack <- c(stack, neighbor)
        }
      }
    }
  }
  interior
}

new_position <- function(player, boxes) {
  list(player = player, boxes = boxes)
}

same_position <- function(a, b) {
  a$player == b$player && length(a$boxes) == length(b$boxes) && all(a$boxes == b$boxes)
}

new_level <- function(height, width, walls, goals, interior) {
  list(
    height = height,
    width = width,
    size = height * width,
    walls = walls,
    goals = goals,
    interior = interior,
    offsets = vapply(DELTAS, function(delta) delta[1] * width + delta[2], numeric(1)),
    goal_cells = which(goals),
    reason = NULL,
    distances = list(),
    dead = logical(height * width)
  )
}

cell_text <- function(level, cell) {
  paste((cell - 1) %/% level$width + 1, (cell - 1) %% level$width + 1)
}

cell_at <- function(level, row, column) {
  (row - 1) * level$width + column
}

contains_cell <- function(level, row, column) {
  row >= 1 && row <= level$height && column >= 1 && column <= level$width
}

on_border <- function(level, cell) {
  row <- (cell - 1) %/% level$width
  column <- (cell - 1) %% level$width
  row == 0 | row == level$height - 1 | column == 0 | column == level$width - 1
}

invalidity <- function(level, players, boxes) {
  if (players != 1) {
    return(paste("players", players))
  }
  if (length(boxes) == 0) {
    return("no boxes")
  }
  if (length(boxes) != length(level$goal_cells)) {
    return(paste("boxes", length(boxes), "goals", length(level$goal_cells)))
  }
  cells <- seq_len(level$size)
  open_cells <- which(level$interior & on_border(level, cells))
  if (length(open_cells) > 0) {
    return(paste("open", cell_text(level, open_cells[1])))
  }
  outside_cells <- which((level$goals | cells %in% boxes) & !level$interior)
  if (length(outside_cells) > 0) {
    return(paste("outside", cell_text(level, outside_cells[1])))
  }
  NULL
}

analyze <- function(level) {
  level$distances <- lapply(level$goal_cells, function(goal) push_distances(level, goal))
  level$dead <- vapply(seq_len(level$size), function(cell) {
    level$interior[cell] && is.na(goal_distance(level, cell))
  }, logical(1))
  level
}

push_distances <- function(level, goal) {
  distance <- rep(NA_integer_, level$size)
  distance[goal] <- 0L
  queue <- goal
  while (length(queue) > 0) {
    cell <- queue[1]
    queue <- queue[-1]
    for (direction in DIRECTIONS) {
      offset <- level$offsets[[direction]]
      box <- cell - offset
      if (level$interior[box] && level$interior[box - offset] && is.na(distance[box])) {
        distance[box] <- distance[cell] + 1L
        queue <- c(queue, box)
      }
    }
  }
  distance
}

goal_distance <- function(level, cell) {
  distances <- vapply(level$distances, function(distance) distance[cell], integer(1))
  if (all(is.na(distances))) NA_integer_ else min(distances, na.rm = TRUE)
}

boxes_on_goals <- function(level, boxes) {
  sum(level$goals[boxes])
}

solved <- function(level, boxes) {
  boxes_on_goals(level, boxes) == length(boxes)
}

reachable <- function(level, player, boxes) {
  seen <- logical(level$size)
  seen[player] <- TRUE
  stack <- player
  while (length(stack) > 0) {
    cell <- stack[length(stack)]
    stack <- stack[-length(stack)]
    for (offset in level$offsets) {
      neighbor <- cell + offset
      if (level$interior[neighbor] && !seen[neighbor] && !(neighbor %in% boxes)) {
        seen[neighbor] <- TRUE
        stack <- c(stack, neighbor)
      }
    }
  }
  seen
}

representative <- function(level, player, boxes) {
  which(reachable(level, player, boxes))[1]
}

walk_path <- function(level, start, target, boxes) {
  came_from <- rep(NA_integer_, level$size)
  came_by <- rep(NA_character_, level$size)
  queue <- start
  while (length(queue) > 0) {
    cell <- queue[1]
    queue <- queue[-1]
    for (direction in DIRECTIONS) {
      neighbor <- cell + level$offsets[[direction]]
      if (level$interior[neighbor] && !(neighbor %in% boxes) && neighbor != start &&
        is.na(came_from[neighbor])) {
        came_from[neighbor] <- cell
        came_by[neighbor] <- direction
        queue <- c(queue, neighbor)
      }
    }
  }
  directions <- character(0)
  cell <- target
  while (cell != start) {
    directions <- c(came_by[cell], directions)
    cell <- came_from[cell]
  }
  directions
}

take_step <- function(level, position, direction) {
  offset <- level$offsets[[direction]]
  target <- position$player + offset
  if (level$walls[target]) {
    step_failure("wall")
  }
  if (!(target %in% position$boxes)) {
    return(list(position = new_position(target, position$boxes), letter = direction))
  }
  beyond <- target + offset
  if (level$walls[beyond] || beyond %in% position$boxes) {
    step_failure("blocked")
  }
  boxes <- move_box(position$boxes, target, beyond)
  list(position = new_position(target, boxes), letter = toupper(direction))
}

pushable <- function(level, box, direction, boxes, reachable_cells) {
  offset <- level$offsets[[direction]]
  destination <- box + offset
  reachable_cells[box - offset] && level$interior[destination] && !(destination %in% boxes)
}

side_blocked <- function(level, box, sides, boxes, assumed) {
  if (any(level$walls[sides] | sides %in% assumed)) {
    return(TRUE)
  }
  if (all(level$dead[sides])) {
    return(TRUE)
  }
  extended <- c(assumed, box)
  for (side in sides) {
    if (side %in% boxes && frozen(level, side, boxes, extended)) {
      return(TRUE)
    }
  }
  FALSE
}

frozen <- function(level, box, boxes, assumed = integer(0)) {
  horizontal <- box + level$offsets[c("l", "r")]
  vertical <- box + level$offsets[c("u", "d")]
  side_blocked(level, box, horizontal, boxes, assumed) &&
    side_blocked(level, box, vertical, boxes, assumed)
}

has_frozen_box <- function(level, boxes) {
  for (box in boxes) {
    if (!level$goals[box] && frozen(level, box, boxes)) {
      return(TRUE)
    }
  }
  FALSE
}

split_rows <- function(level, symbols) {
  starts <- seq(1, level$size, by = level$width)
  vapply(starts, function(start) {
    paste(symbols[start:(start + level$width - 1)], collapse = "")
  }, character(1))
}

render <- function(level, position) {
  boxes <- position$boxes
  symbols <- ifelse(level$goals, ".", "-")
  symbols[boxes] <- ifelse(level$goals[boxes], "*", "$")
  symbols[position$player] <- if (level$goals[position$player]) "+" else "@"
  symbols[level$walls] <- "#"
  split_rows(level, symbols)
}

dead_map <- function(level) {
  symbols <- ifelse(level$dead, "x", "-")
  symbols[level$goals] <- "."
  symbols[level$walls] <- "#"
  split_rows(level, symbols)
}

map_cell <- function(level, kind, cell) {
  row <- (cell - 1) %/% level$width
  column <- (cell - 1) %% level$width
  last_row <- level$height - 1
  last_column <- level$width - 1
  moved <- switch(kind,
    ROT90 = column * level$height + last_row - row,
    ROT180 = (last_row - row) * level$width + last_column - column,
    ROT270 = (last_column - column) * level$height + row,
    FLIPH = row * level$width + last_column - column,
    FLIPV = (last_row - row) * level$width + column
  )
  moved + 1
}

map_position <- function(level, kind, position) {
  boxes <- sort(map_cell(level, kind, position$boxes))
  new_position(map_cell(level, kind, position$player), boxes)
}

transformed <- function(level, kind) {
  moved <- map_cell(level, kind, seq_len(level$size))
  walls <- logical(level$size)
  walls[moved] <- level$walls
  goals <- logical(level$size)
  goals[moved] <- level$goals
  interior <- logical(level$size)
  interior[moved] <- level$interior
  rotated <- kind %in% c("ROT90", "ROT270")
  height <- if (rotated) level$width else level$height
  width <- if (rotated) level$height else level$width
  analyze(new_level(height, width, walls, goals, interior))
}

build_level <- function(rows) {
  height <- length(rows)
  width <- nchar(rows[1])
  cells <- unlist(strsplit(rows, ""))
  walls <- cells == "#"
  goals <- cells %in% c(".", "*", "+")
  players <- which(cells %in% c("@", "+"))
  boxes <- which(cells %in% c("$", "*"))
  interior <- if (length(players) == 1) {
    find_interior(height, width, walls, players)
  } else {
    logical(length(cells))
  }
  level <- new_level(height, width, walls, goals, interior)
  level$reason <- invalidity(level, length(players), boxes)
  if (is.null(level$reason)) {
    level <- analyze(level)
  }
  player <- if (length(players) > 0) players[1] else NA_integer_
  list(level = level, position = new_position(player, boxes))
}

state_key <- function(boxes, representative) {
  paste(c(boxes, representative), collapse = ",")
}

solution_pushes <- function(nodes) {
  pushes <- list()
  node <- nodes[[length(nodes)]]
  while (!is.na(node$parent)) {
    pushes <- c(list(node$push), pushes)
    node <- nodes[[node$parent]]
  }
  pushes
}

solution_notation <- function(level, position, pushes) {
  pieces <- character(0)
  for (push in pushes) {
    offset <- level$offsets[[push$direction]]
    path <- walk_path(level, position$player, push$box - offset, position$boxes)
    pieces <- c(pieces, path, toupper(push$direction))
    boxes <- move_box(position$boxes, push$box, push$box + offset)
    position <- new_position(push$box, boxes)
  }
  paste(pieces, collapse = "")
}

push_search <- function(level, start, fixed, target, pruning, limit) {
  root <- list(
    boxes = start$boxes,
    representative = representative(level, start$player, start$boxes),
    parent = NA,
    push = NULL
  )
  nodes <- list(root)
  known <- new.env(hash = TRUE)
  known[[state_key(root$boxes, root$representative)]] <- TRUE
  expanded <- 0L
  while (expanded < length(nodes)) {
    if (!is.null(limit) && expanded == limit) {
      return(list(outcome = "limit", expanded = expanded, states = length(nodes)))
    }
    expanded <- expanded + 1L
    node <- nodes[[expanded]]
    reachable_cells <- reachable(level, node$representative, node$boxes)
    for (box in node$boxes) {
      if (box %in% fixed) {
        next
      }
      for (direction in DIRECTIONS) {
        if (!pushable(level, box, direction, node$boxes, reachable_cells)) {
          next
        }
        destination <- box + level$offsets[[direction]]
        boxes <- move_box(node$boxes, box, destination)
        if (pruning && (level$dead[destination] || has_frozen_box(level, boxes))) {
          next
        }
        first_cell <- representative(level, box, boxes)
        key <- state_key(boxes, first_cell)
        if (!is.null(known[[key]])) {
          next
        }
        known[[key]] <- TRUE
        nodes[[length(nodes) + 1]] <- list(
          boxes = boxes,
          representative = first_cell,
          parent = expanded,
          push = list(box = box, direction = direction)
        )
        reached <- if (is.null(target)) solved(level, boxes) else destination == target
        if (reached) {
          notation <- solution_notation(level, start, solution_pushes(nodes))
          return(list(
            outcome = "found", expanded = expanded, states = length(nodes),
            notation = notation
          ))
        }
      }
    }
  }
  list(outcome = "no solution", expanded = expanded, states = length(nodes))
}

new_game <- function(rows) {
  game <- new.env()
  load_level(game, rows)
  game
}

load_level <- function(game, rows) {
  built <- build_level(rows)
  game$level <- built$level
  game$initial <- built$position
  game$current <- built$position
  game$history <- character(0)
  game$redo_list <- character(0)
  game$snapshots <- list()
  game$solution <- NULL
}

cell_argument <- function(game, arguments, index) {
  cell_at(game$level, as.integer(arguments[index]), as.integer(arguments[index + 1]))
}

simulate <- function(game, directions) {
  position <- game$current
  moves <- character(0)
  failure <- tryCatch(
    {
      for (direction in directions) {
        result <- take_step(game$level, position, direction)
        position <- result$position
        moves <- c(moves, result$letter)
      }
      NULL
    },
    step_failure = function(condition) {
      paste("step", length(moves) + 1, conditionMessage(condition))
    }
  )
  list(position = position, moves = moves, failure = failure)
}

take_steps <- function(game, directions) {
  simulation <- simulate(game, directions)
  game$current <- simulation$position
  game$history <- c(game$history, simulation$moves)
  if (length(simulation$moves) > 0) {
    game$redo_list <- character(0)
  }
  simulation
}

progress <- function(game, boxes) {
  on_goals <- boxes_on_goals(game$level, boxes)
  text <- paste0("goals ", on_goals, "/", length(boxes))
  if (on_goals == length(boxes)) paste(text, "solved") else text
}

search_solution <- function(game, limit) {
  if (solved(game$level, game$current$boxes)) {
    return(list(text = "already solved", notation = NULL))
  }
  result <- push_search(game$level, game$current, integer(0), NULL, TRUE, limit)
  counts <- paste("expanded", result$expanded, "states", result$states)
  if (result$outcome != "found") {
    return(list(text = paste(result$outcome, counts), notation = NULL))
  }
  notation <- chars(result$notation)
  text <- paste("solution pushes", push_count(notation), "moves", length(notation), counts)
  list(text = text, notation = result$notation)
}

load_rows <- function(game, width, rows) {
  for (number in seq_along(rows)) {
    row <- rows[number]
    if (nchar(row) != width || !all(chars(row) %in% LEVEL_CHARACTERS)) {
      command_error(paste("bad row", number))
    }
  }
  load_level(game, rows)
  emit("loaded", paste0(length(rows), "x", width))
}

command_import <- function(game, arguments) {
  rows <- lapply(split_at_bars(arguments[1]), decode, allowed = LEVEL_CHARACTERS)
  if (any(vapply(rows, is.null, logical(1))) || length(rows) > MAX_SIDE) {
    command_error("bad level")
  }
  rows <- unlist(rows)
  width <- nchar(rows[1])
  if (any(nchar(rows) != width) || width < 1 || width > MAX_SIDE) {
    command_error("bad level")
  }
  load_level(game, rows)
  emit("loaded", paste0(length(rows), "x", width))
}

command_valid <- function(game, arguments) {
  reason <- game$level$reason
  if (is.null(reason)) {
    emit("valid")
  } else {
    emit("invalid", reason)
  }
}

command_info <- function(game, arguments) {
  level <- game$level
  emit(
    "size", paste0(level$height, "x", level$width), "walls", sum(level$walls),
    "cells", sum(level$interior), "boxes", length(game$current$boxes),
    "dead", sum(level$dead)
  )
}

command_show <- function(game, arguments) {
  writeLines(render(game$level, game$current))
}

command_export <- function(game, arguments) {
  rows <- render(game$level, game$current)
  emit("level", paste(vapply(rows, encode, character(1)), collapse = "|"))
}

command_move <- function(game, arguments) {
  simulation <- take_steps(game, step_sequence(arguments[1]))
  if (length(simulation$moves) > 0) {
    emit("moved", paste(simulation$moves, collapse = ""))
  }
  if (!is.null(simulation$failure)) {
    command_error(simulation$failure)
  }
}

command_push <- function(game, arguments) {
  level <- game$level
  position <- game$current
  box <- cell_argument(game, arguments, 1)
  direction <- arguments[3]
  offset <- level$offsets[[direction]]
  if (!(box %in% position$boxes)) {
    command_error("no box")
  }
  destination <- box + offset
  if (!level$interior[destination] || destination %in% position$boxes) {
    command_error("blocked")
  }
  if (!reachable(level, position$player, position$boxes)[box - offset]) {
    command_error("unreachable")
  }
  path <- walk_path(level, position$player, box - offset, position$boxes)
  simulation <- take_steps(game, c(path, direction))
  emit("pushed", paste(simulation$moves, collapse = ""))
}

command_bring <- function(game, arguments) {
  position <- game$current
  origin <- cell_argument(game, arguments, 1)
  target <- cell_argument(game, arguments, 3)
  if (!(origin %in% position$boxes)) {
    command_error("no box")
  }
  if (origin == target) {
    emit("brought 0")
    return()
  }
  fixed <- setdiff(position$boxes, origin)
  result <- push_search(game$level, position, fixed, target, FALSE, NULL)
  if (result$outcome != "found") {
    command_error("no route")
  }
  notation <- chars(result$notation)
  take_steps(game, tolower(notation))
  emit("brought", push_count(notation), result$notation)
}

command_path <- function(game, arguments) {
  level <- game$level
  position <- game$current
  target <- cell_argument(game, arguments, 1)
  if (!reachable(level, position$player, position$boxes)[target]) {
    command_error("unreachable")
  }
  path <- walk_path(level, position$player, target, position$boxes)
  emit(counted("path", take_steps(game, path)$moves))
}

command_undo <- function(game, arguments) {
  if (length(game$history) == 0) {
    command_error("nothing to undo")
  }
  count <- min(as.integer(arguments[1]), length(game$history))
  for (index in seq_len(count)) {
    letter <- game$history[length(game$history)]
    game$history <- game$history[-length(game$history)]
    direction <- tolower(letter)
    offset <- game$level$offsets[[direction]]
    player <- game$current$player
    boxes <- game$current$boxes
    if (is_push(letter)) {
      boxes <- move_box(boxes, player + offset, player)
    }
    game$current <- new_position(player - offset, boxes)
    game$redo_list <- c(game$redo_list, direction)
  }
  emit("undone", count)
}

command_redo <- function(game, arguments) {
  if (length(game$redo_list) == 0) {
    command_error("nothing to redo")
  }
  count <- min(as.integer(arguments[1]), length(game$redo_list))
  for (index in seq_len(count)) {
    direction <- game$redo_list[length(game$redo_list)]
    game$redo_list <- game$redo_list[-length(game$redo_list)]
    result <- take_step(game$level, game$current, direction)
    game$current <- result$position
    game$history <- c(game$history, result$letter)
  }
  emit("redone", count)
}

command_reset <- function(game, arguments) {
  game$current <- game$initial
  game$history <- character(0)
  game$redo_list <- character(0)
  emit("reset")
}

command_status <- function(game, arguments) {
  emit(
    "moves", length(game$history), "pushes", push_count(game$history),
    progress(game, game$current$boxes)
  )
}

command_history <- function(game, arguments) {
  emit(counted("history", game$history))
}

command_boxes <- function(game, arguments) {
  level <- game$level
  position <- game$current
  reachable_cells <- reachable(level, position$player, position$boxes)
  emit("boxes", length(position$boxes))
  for (box in position$boxes) {
    distance <- goal_distance(level, box)
    directions <- Filter(function(direction) {
      pushable(level, box, direction, position$boxes, reachable_cells)
    }, DIRECTIONS)
    emit(
      "box", cell_text(level, box), if (is.na(distance)) "dead" else distance,
      if (length(directions) == 0) "-" else paste(directions, collapse = "")
    )
  }
}

command_reach <- function(game, arguments) {
  level <- game$level
  reachable_cells <- reachable(level, game$current$player, game$current$boxes)
  emit("reach", sum(reachable_cells), "first", cell_text(level, which(reachable_cells)[1]))
}

command_dead_squares <- function(game, arguments) {
  emit("dead", sum(game$level$dead))
  writeLines(dead_map(game$level))
}

command_deadlock <- function(game, arguments) {
  level <- game$level
  boxes <- game$current$boxes
  for (box in boxes) {
    if (level$dead[box]) {
      emit("deadlock dead", cell_text(level, box))
      return()
    }
  }
  for (box in boxes) {
    if (!level$goals[box] && frozen(level, box, boxes)) {
      emit("deadlock frozen", cell_text(level, box))
      return()
    }
  }
  emit("no deadlock")
}

command_bound <- function(game, arguments) {
  level <- game$level
  boxes <- game$current$boxes
  best <- NULL
  for (order in permutations(seq_along(level$goal_cells))) {
    pushes <- mapply(function(box, goal) level$distances[[goal]][box], boxes, order)
    if (anyNA(pushes)) {
      next
    }
    if (is.null(best) || sum(pushes) < sum(best$pushes)) {
      best <- list(order = order, pushes = pushes)
    }
  }
  if (is.null(best)) {
    emit("bound none")
    return()
  }
  emit("bound", sum(best$pushes))
  for (index in seq_along(boxes)) {
    goal <- level$goal_cells[best$order[index]]
    emit(
      "box", cell_text(level, boxes[index]), "goal", cell_text(level, goal),
      "pushes", best$pushes[index]
    )
  }
}

command_save <- function(game, arguments) {
  name <- arguments[1]
  game$snapshots[[name]] <- list(position = game$current, history = game$history)
  emit("saved", name, "moves", length(game$history))
}

command_restore <- function(game, arguments) {
  name <- arguments[1]
  snapshot <- game$snapshots[[name]]
  if (is.null(snapshot)) {
    command_error(paste("no snapshot", name))
  }
  game$current <- snapshot$position
  game$history <- snapshot$history
  game$redo_list <- character(0)
  emit("restored", name, "moves", length(game$history))
}

command_check <- function(game, arguments) {
  simulation <- simulate(game, step_sequence(arguments[1]))
  if (!is.null(simulation$failure)) {
    emit("check fail", simulation$failure)
    return()
  }
  moves <- simulation$moves
  emit(
    "check ok moves", length(moves), "pushes", push_count(moves),
    progress(game, simulation$position$boxes)
  )
}

command_solve <- function(game, arguments) {
  attempt <- search_solution(game, as.integer(arguments[1]))
  emit(attempt$text)
  game$solution <- NULL
  if (!is.null(attempt$notation)) {
    emit(attempt$notation)
    game$solution <- list(notation = attempt$notation, position = game$current)
  }
}

command_hint <- function(game, arguments) {
  attempt <- search_solution(game, as.integer(arguments[1]))
  if (is.null(attempt$notation)) {
    emit(attempt$text)
    return()
  }
  notation <- chars(attempt$notation)
  part <- notation[seq_len(which(is_push(notation))[1])]
  take_steps(game, tolower(part))
  emit("hint", paste(part, collapse = ""))
}

command_play <- function(game, arguments) {
  solution <- game$solution
  if (is.null(solution) || !same_position(solution$position, game$current)) {
    command_error("no solution")
  }
  notation <- chars(solution$notation)
  take_steps(game, tolower(notation))
  emit("played pushes", push_count(notation), "moves", length(notation))
}

command_transform <- function(game, arguments) {
  kind <- arguments[1]
  old <- game$level
  game$level <- transformed(old, kind)
  game$initial <- map_position(old, kind, game$initial)
  game$current <- map_position(old, kind, game$current)
  game$history <- turn_letters(game$history, kind)
  game$redo_list <- turn_letters(game$redo_list, kind)
  game$snapshots <- lapply(game$snapshots, function(snapshot) {
    list(
      position = map_position(old, kind, snapshot$position),
      history = turn_letters(snapshot$history, kind)
    )
  })
  solution <- game$solution
  if (!is.null(solution)) {
    game$solution <- list(
      notation = paste(turn_letters(chars(solution$notation), kind), collapse = ""),
      position = map_position(old, kind, solution$position)
    )
  }
  emit("transformed", paste0(game$level$height, "x", game$level$width))
}

HANDLERS <- list(
  IMPORT = command_import,
  VALID = command_valid,
  INFO = command_info,
  SHOW = command_show,
  EXPORT = command_export,
  MOVE = command_move,
  PUSH = command_push,
  BRING = command_bring,
  PATH = command_path,
  UNDO = command_undo,
  REDO = command_redo,
  RESET = command_reset,
  STATUS = command_status,
  HISTORY = command_history,
  BOXES = command_boxes,
  REACH = command_reach,
  DEADSQUARES = command_dead_squares,
  DEADLOCK = command_deadlock,
  BOUND = command_bound,
  SAVE = command_save,
  RESTORE = command_restore,
  CHECK = command_check,
  SOLVE = command_solve,
  HINT = command_hint,
  PLAY = command_play,
  TRANSFORM = command_transform
)

check_values <- function(game, name, arguments) {
  cells <- if (name %in% names(CELL_COUNTS)) CELL_COUNTS[[name]] else 0
  for (index in seq_len(cells) * 2 - 1) {
    row <- as.integer(arguments[index])
    column <- as.integer(arguments[index + 1])
    if (!contains_cell(game$level, row, column)) {
      command_error("bad value")
    }
  }
  if (name %in% c("UNDO", "REDO") && as.integer(arguments[1]) < 1) {
    command_error("bad value")
  }
  if (name %in% c("SOLVE", "HINT")) {
    limit <- as.integer(arguments[1])
    if (limit < 1 || limit > MAX_LIMIT) {
      command_error("bad value")
    }
  }
}

run_command <- function(game, name, arguments) {
  if (!(name %in% names(COMMANDS))) {
    command_error(paste("unknown command", name))
  }
  kinds <- COMMANDS[[name]]
  well_formed <- length(arguments) == length(kinds) && all(vapply(
    seq_along(kinds),
    function(index) valid_argument(kinds[index], arguments[index]),
    logical(1)
  ))
  if (!well_formed) {
    command_error("bad arguments")
  }
  if (!(name %in% LEVEL_FREE_COMMANDS)) {
    if (!is.null(game$level$reason)) {
      command_error("invalid level")
    }
    check_values(game, name, arguments)
  }
  HANDLERS[[name]](game, arguments)
}

execute <- function(game, words, rows) {
  tryCatch(
    if (words[1] == "LOAD") {
      load_rows(game, as.integer(words[3]), rows)
    } else {
      run_command(game, words[1], words[-1])
    },
    command_error = function(error) emit("error:", conditionMessage(error))
  )
}

main <- function() {
  input <- file("stdin", "r")
  on.exit(close(input))
  height <- as.integer(strsplit(readLines(input, n = 1), " ")[[1]][1])
  game <- new_game(readLines(input, n = height))
  count <- as.integer(readLines(input, n = 1))
  for (index in seq_len(count)) {
    words <- strsplit(readLines(input, n = 1), " ")[[1]]
    rows <- if (words[1] == "LOAD") readLines(input, n = as.integer(words[2])) else character(0)
    execute(game, words, rows)
  }
}

main()
