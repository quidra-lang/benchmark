directions <- c("north", "south", "east", "west", "up", "down")
verbs <- c(go = "go", walk = "go", run = "go", look = "look", l = "look",
  examine = "examine", x = "examine", inspect = "examine", read = "examine",
  take = "take", get = "take", grab = "take", drop = "drop", discard = "drop",
  put = "put", insert = "put", place = "put", inventory = "inventory", inv = "inventory", i = "inventory",
  open = "open", close = "close", shut = "close", unlock = "unlock", lock = "lock", use = "use", apply = "use",
  light = "light", ignite = "light", extinguish = "extinguish", douse = "extinguish", snuff = "extinguish",
  wait = "wait", z = "wait", score = "score", save = "save", restore = "restore", load = "restore",
  verbose = "verbose", brief = "brief")
actions <- c("go", "take", "drop", "put", "open", "close", "unlock", "lock", "use", "light", "extinguish", "wait")
no_arguments <- c("look", "inventory", "wait", "score", "save", "restore", "verbose", "brief")
player <- 0L
nowhere <- -1L

say <- function(text) if (length(text)) cat(paste0(text, "\n"), sep = "")
fail <- function(message) {
  stop(structure(list(message = message, call = NULL), class = c("adventure_error", "error", "condition")))
}
joined <- function(values) paste(values, collapse = " ")
after <- function(values, index) if (index >= length(values)) character() else values[seq.int(index + 1L, length(values))]
command_words <- function(text) {
  tokens <- strsplit(chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", text), " +")[[1L]]
  tokens[!tokens %in% c("the", "a", "an")]
}
direction <- function(word) {
  index <- match(word, c(directions, substr(directions, 1L, 1L)), nomatch = 0L)
  if (index == 0L) 0L else (index - 1L) %% 6L + 1L
}
all_items <- function(phrase) identical(phrase, "all")
inside <- function(game, item) game$room_count + item

new_game <- function(definitions) {
  game <- new.env(parent = emptyenv())
  kinds <- vapply(definitions, `[[`, character(1L), 1L)
  room_ids <- vapply(definitions[kinds == "ROOM"], `[[`, character(1L), 2L)
  item_ids <- sort(vapply(definitions[kinds == "ITEM"], `[[`, character(1L), 2L), method = "radix")
  room_index <- setNames(seq_along(room_ids), room_ids)
  item_index <- setNames(seq_along(item_ids), item_ids)
  game$room_count <- length(room_ids)
  game$rooms <- lapply(room_ids, function(id) list(name = "", dark = FALSE, description = character()))
  game$items <- lapply(item_ids, function(id) list(id = id, name = "", words = character(), nouns = id,
    weight = 0L, treasure = 0L, light = FALSE, capacity = 0L, key = 0L, fixed = FALSE, details = character()))
  game$state <- list(room = 1L, places = integer(length(item_ids)), containers = rep("open", length(item_ids)),
    destinations = matrix(0L, game$room_count, 6L), keys = matrix(0L, game$room_count, 6L),
    locked = matrix(FALSE, game$room_count, 6L), lit = rep(FALSE, length(item_ids)), fuel = integer(length(item_ids)),
    flags = character(), bonus = 0L, moves = 0L, visited = rep(FALSE, game$room_count), darkness = 0L, ended = "none")
  game$rules <- list()
  game$pronoun <- 0L
  game$previous <- NULL
  game$verbose <- FALSE
  game$saved <- NULL
  for (tokens in definitions) switch(tokens[1L],
    ROOM = {
      room <- room_index[[tokens[2L]]]
      dark <- tokens[3L] == "DARK"
      game$rooms[[room]]$name <- joined(after(tokens, if (dark) 3L else 2L))
      game$rooms[[room]]$dark <- dark
    },
    DESC = {
      room <- room_index[[tokens[2L]]]
      game$rooms[[room]]$description <- c(game$rooms[[room]]$description, joined(after(tokens, 2L)))
    },
    EXIT = {
      room <- room_index[[tokens[2L]]]
      d <- direction(tokens[3L])
      game$state$destinations[room, d] <- room_index[[tokens[4L]]]
      if (length(tokens) > 4L) {
        game$state$keys[room, d] <- item_index[[tokens[6L]]]
        game$state$locked[room, d] <- TRUE
      }
    },
    ITEM = {
      item <- item_index[[tokens[2L]]]
      game$state$places[item] <- if (tokens[3L] == "PLAYER") player else if (tokens[3L] == "NOWHERE") nowhere else room_index[[tokens[3L]]]
      value <- game$items[[item]]
      value$weight <- as.integer(tokens[4L])
      position <- 5L
      if (tokens[position] == "TREASURE") { value$treasure <- as.integer(tokens[position + 1L]); position <- position + 2L }
      if (tokens[position] == "LIGHT") {
        value$light <- TRUE
        game$state$fuel[item] <- as.integer(tokens[position + 1L])
        position <- position + 2L
      }
      if (tokens[position] == "CONTAINER") {
        value$capacity <- as.integer(tokens[position + 1L])
        position <- position + 2L
        if (tokens[position] == "CLOSED") { game$state$containers[item] <- "closed"; position <- position + 1L }
        if (tokens[position] == "LOCKED") {
          value$key <- item_index[[tokens[position + 1L]]]
          game$state$containers[item] <- "locked"
          position <- position + 2L
        }
      }
      if (tokens[position] == "FIXED") { value$fixed <- TRUE; position <- position + 1L }
      value$words <- after(tokens, position - 1L)
      value$name <- joined(value$words)
      game$items[[item]] <- value
    },
    INSIDE = game$state$places[item_index[[tokens[2L]]]] <- inside(game, item_index[[tokens[3L]]]),
    ALIAS = {
      item <- item_index[[tokens[2L]]]
      game$items[[item]]$nouns <- union(game$items[[item]]$nouns, tokens[3L])
    },
    DETAIL = {
      item <- item_index[[tokens[2L]]]
      game$items[[item]]$details <- c(game$items[[item]]$details, joined(after(tokens, 2L)))
    },
    RULE = , ENTER = {
      use <- tokens[1L] == "RULE"
      rule <- list(kind = if (use) "use" else "enter", a = if (use) item_index[[tokens[2L]]] else room_index[[tokens[2L]]],
                   b = if (use) item_index[[tokens[3L]]] else 0L, condition = NULL)
      position <- if (use) 4L else 3L
      if (tokens[position] %in% c("IF", "UNLESS")) {
        rule$condition <- list(flag = tokens[position + 1L], on = tokens[position] == "IF")
        position <- position + 2L
      }
      args <- after(tokens, position)
      rule$effect <- switch(tokens[position],
        MESSAGE = list(kind = "message", text = joined(args)),
        OPEN = list(kind = "open", room = room_index[[args[1L]]], direction = direction(args[2L]), destination = room_index[[args[3L]]]),
        REMOVE = list(kind = "move", item = item_index[[args[1L]]], place = nowhere),
        ADD = list(kind = "move", item = item_index[[args[1L]]], place = room_index[[args[2L]]]),
        SET = list(kind = "flag", flag = args[1L], on = TRUE),
        CLEAR = list(kind = "flag", flag = args[1L], on = FALSE),
        POINTS = list(kind = "points", value = as.integer(args[1L])))
      game$rules[[length(game$rules) + 1L]] <- rule
    },
    TROPHY = game$trophy <- room_index[[tokens[2L]]],
    START = game$state$room <- room_index[[tokens[2L]]],
    MAXWEIGHT = game$max_weight <- as.integer(tokens[2L]))
  game$state$visited[game$state$room] <- TRUE
  game$vocabulary <- unique(c(character(), unlist(lapply(game$items, function(item) c(item$nouns, item$words)), use.names = FALSE)))
  game
}

direct <- function(game, place) which(game$state$places == place)
reachable <- function(game, item, root) {
  place <- game$state$places[item]
  while (place > game$room_count) {
    item <- place - game$room_count
    if (game$state$containers[item] != "open") return(FALSE)
    place <- game$state$places[item]
  }
  place == root
}
carried <- function(game, item) reachable(game, item, player)
room_item <- function(game, item) reachable(game, item, game$state$room)
nearby <- function(game) vapply(seq_along(game$items), function(i) carried(game, i) || room_item(game, i), logical(1L))
is_lit <- function(game) !game$rooms[[game$state$room]]$dark || any(game$state$lit & nearby(game))
visible <- function(game) {
  lit <- is_lit(game)
  vapply(seq_along(game$items), function(i) carried(game, i) || (lit && room_item(game, i)), logical(1L))
}
within <- function(game, item, ancestor) {
  place <- game$state$places[item]
  while (place > game$room_count) {
    item <- place - game$room_count
    if (item == ancestor) return(TRUE)
    place <- game$state$places[item]
  }
  FALSE
}
total_weight <- function(game, item) game$items[[item]]$weight + place_weight(game, inside(game, item))
place_weight <- function(game, place) sum(vapply(direct(game, place), function(i) total_weight(game, i), integer(1L)))
stored <- function(game, item) {
  place <- game$state$places[item]
  while (place > game$room_count) place <- game$state$places[place - game$room_count]
  place == game$trophy
}
treasures <- function(game) {
  values <- vapply(game$items, `[[`, integer(1L), "treasure")
  present <- values > 0L
  collected <- present & vapply(seq_along(game$items), function(i) stored(game, i), logical(1L))
  list(points = sum(values[collected]), stored = sum(collected), total = sum(present))
}
score <- function(game) treasures(game)$points + game$state$bonus
item_names <- function(game, indices) paste(vapply(game$items[indices], `[[`, character(1L), "name"), collapse = ", ")
display_name <- function(game, item) {
  annotations <- character()
  if (game$items[[item]]$capacity > 0L) annotations <- game$state$containers[item]
  if (game$state$lit[item]) annotations <- c(annotations, "lit")
  paste0(game$items[[item]]$name, if (length(annotations)) paste0(" (", paste(annotations, collapse = ", "), ")") else "")
}
item_tree <- function(game, place, depth) {
  for (item in direct(game, place)) {
    say(paste0(strrep(" ", 2L * depth), display_name(game, item)))
    if (game$items[[item]]$capacity > 0L && game$state$containers[item] == "open") item_tree(game, inside(game, item), depth + 1L)
  }
}
describe <- function(game, full) {
  if (!is_lit(game)) { say("It is pitch dark."); return(invisible(NULL)) }
  room <- game$state$room
  say(game$rooms[[room]]$name)
  if (full) say(game$rooms[[room]]$description)
  exits <- which(game$state$destinations[room, ] != 0L)
  text <- if (length(exits)) paste0(directions[exits], ifelse(game$state$locked[room, exits], " (locked)", "")) else "none"
  say(paste0("Exits: ", paste(text, collapse = ", ")))
  if (length(direct(game, room))) { say("You see:"); item_tree(game, room, 1L) }
}
resolve <- function(game, phrase) {
  seen <- visible(game)
  if (identical(phrase, "it")) {
    if (game$pronoun == 0L) fail('I don\'t know what "it" refers to.')
    if (!seen[game$pronoun]) fail("You can't see any such thing.")
    return(game$pronoun)
  }
  for (word in phrase) if (!word %in% game$vocabulary) fail(paste0('I don\'t know the word "', word, '".'))
  noun <- tail(phrase, 1L)
  adjectives <- head(phrase, -1L)
  matches <- which(seen & vapply(game$items, function(item) noun %in% item$nouns && all(adjectives %in% item$words), logical(1L)))
  if (!length(matches)) fail("You can't see any such thing.")
  if (length(matches) > 1L) fail(paste0("Which do you mean: ", item_names(game, matches), "?"))
  game$pronoun <- matches[1L]
  game$pronoun
}

run_rules <- function(game, kind, a, b = 0L) {
  executed <- 0L
  message <- FALSE
  for (rule in game$rules) {
    if (rule$kind != kind || rule$a != a || rule$b != b) next
    condition <- rule$condition
    if (!is.null(condition) && (condition$flag %in% game$state$flags) != condition$on) next
    executed <- executed + 1L
    effect <- rule$effect
    switch(effect$kind,
      message = { say(effect$text); message <- TRUE },
      open = {
        game$state$destinations[effect$room, effect$direction] <- effect$destination
        game$state$keys[effect$room, effect$direction] <- 0L
        game$state$locked[effect$room, effect$direction] <- FALSE
      },
      move = game$state$places[effect$item] <- effect$place,
      flag = game$state$flags <- if (effect$on) union(game$state$flags, effect$flag) else setdiff(game$state$flags, effect$flag),
      points = game$state$bonus <- game$state$bonus + effect$value)
  }
  list(executed = executed, message = message)
}
pass_turn <- function(game, baseline) {
  game$state$moves <- game$state$moves + 1L
  close_by <- nearby(game)
  for (item in which(game$state$lit)) {
    game$state$fuel[item] <- game$state$fuel[item] - 1L
    if (game$state$fuel[item] == 0L) {
      game$state$lit[item] <- FALSE
      if (close_by[item]) say(paste0("The ", game$items[[item]]$name, " goes out."))
    }
  }
  lit <- is_lit(game)
  if (baseline && !lit) say("It is now pitch dark.") else if (!baseline && lit) describe(game, TRUE)
  game$state$darkness <- if (lit) 0L else game$state$darkness + 1L
  if (game$state$darkness == 2L) say("You hear something moving in the dark.")
  if (game$state$darkness == 3L) game$state$ended <- "dead"
  treasure <- treasures(game)
  if (game$state$ended == "none" && treasure$total > 0L && treasure$stored == treasure$total) game$state$ended <- "won"
  if (game$state$ended != "none") {
    say(if (game$state$ended == "dead") "*** You have died ***" else "*** You have won ***")
    say(sprintf("You scored %d points in %d moves.", treasure$points + game$state$bonus, game$state$moves))
  }
}
require_container <- function(game, item) {
  if (game$items[[item]]$capacity == 0L) fail(paste0("The ", game$items[[item]]$name, " is not a container."))
  if (game$state$containers[item] != "open") fail(paste0("The ", game$items[[item]]$name, " is closed."))
}
put_item <- function(game, item, container) {
  name <- game$items[[item]]$name
  target <- game$items[[container]]$name
  if (within(game, container, item)) return(paste0("The ", target, " is inside the ", name, "."))
  if (game$state$places[item] == inside(game, container)) return(paste0("The ", name, " is already in the ", target, "."))
  weight <- place_weight(game, inside(game, container)) + if (within(game, item, container)) 0L else total_weight(game, item)
  if (weight > game$items[[container]]$capacity) return(paste0("The ", name, " doesn't fit in the ", target, "."))
  game$state$places[item] <- inside(game, container)
  ""
}
take_items <- function(game, first, second) {
  if (!is_lit(game)) fail("It is pitch dark.")
  container <- 0L
  source <- game$state$room
  if (length(second)) { container <- resolve(game, second); require_container(game, container); source <- inside(game, container) }
  if (all_items(first)) {
    candidates <- direct(game, source)
    candidates <- candidates[!vapply(game$items[candidates], `[[`, logical(1L), "fixed")]
    if (!length(candidates)) fail(if (container == 0L) "There is nothing here to take." else paste0("There is nothing in the ", game$items[[container]]$name, " to take."))
    taken <- FALSE
    for (item in candidates) {
      if (!carried(game, item) && place_weight(game, player) + total_weight(game, item) > game$max_weight) {
        say(paste0(game$items[[item]]$name, ": You can't carry any more."))
      } else {
        game$state$places[item] <- player
        say(paste0(game$items[[item]]$name, ": Taken."))
        taken <- TRUE
      }
    }
    return(taken)
  }
  item <- resolve(game, first)
  name <- game$items[[item]]$name
  if (container != 0L && game$state$places[item] != source) fail(paste0("The ", name, " is not in the ", game$items[[container]]$name, "."))
  if (game$state$places[item] == player) fail(paste0("You already have the ", name, "."))
  if (game$items[[item]]$fixed) fail(paste0("The ", name, " is fixed in place."))
  if (!carried(game, item) && place_weight(game, player) + total_weight(game, item) > game$max_weight) fail("You can't carry any more.")
  game$state$places[item] <- player
  say("Taken.")
  TRUE
}
drop_items <- function(game, phrase) {
  if (all_items(phrase)) {
    candidates <- direct(game, player)
    if (!length(candidates)) fail("You are empty-handed.")
    for (item in candidates) { game$state$places[item] <- game$state$room; say(paste0(game$items[[item]]$name, ": Dropped.")) }
  } else {
    item <- resolve(game, phrase)
    if (!carried(game, item)) fail(paste0("You aren't carrying the ", game$items[[item]]$name, "."))
    game$state$places[item] <- game$state$room
    say("Dropped.")
  }
}
put_items <- function(game, first, second) {
  item <- if (all_items(first)) 0L else resolve(game, first)
  container <- resolve(game, second)
  if (item != 0L) {
    if (!carried(game, item)) fail(paste0("You aren't carrying the ", game$items[[item]]$name, "."))
    if (item == container) fail(paste0("You can't put the ", game$items[[item]]$name, " inside itself."))
  }
  require_container(game, container)
  if (item != 0L) {
    reason <- put_item(game, item, container)
    if (reason != "") fail(reason)
    say(paste0("You put the ", game$items[[item]]$name, " in the ", game$items[[container]]$name, "."))
    return(TRUE)
  }
  candidates <- setdiff(direct(game, player), container)
  if (!length(candidates)) fail(paste0("You have nothing to put in the ", game$items[[container]]$name, "."))
  moved <- FALSE
  for (candidate in candidates) {
    reason <- put_item(game, candidate, container)
    if (reason == "") moved <- TRUE
    say(paste0(game$items[[candidate]]$name, ": ", if (reason == "") "Done." else reason))
  }
  moved
}
key_check <- function(game, key, phrase) {
  if (!length(phrase)) {
    if (!carried(game, key)) fail("You don't have the right key.")
    say(paste0("(with the ", game$items[[key]]$name, ")"))
  } else {
    item <- resolve(game, phrase)
    if (!carried(game, item)) fail(paste0("You aren't carrying the ", game$items[[item]]$name, "."))
    if (item != key) fail(paste0("The ", game$items[[item]]$name, " doesn't fit."))
  }
}
change_lock <- function(game, first, second, locking) {
  d <- if (length(first) == 1L) direction(first) else 0L
  status <- if (locking) "already locked" else "not locked"
  if (d != 0L) {
    room <- game$state$room
    destination <- game$state$destinations[room, d]
    if (destination == 0L) fail(paste0("There is no exit ", directions[d], "."))
    key <- game$state$keys[room, d]
    if (key == 0L) fail(paste0("The way ", directions[d], " has no lock."))
    if (game$state$locked[room, d] == locking) fail(paste0("The way ", directions[d], " is ", status, "."))
    key_check(game, key, second)
    game$state$locked[room, d] <- locking
    opposite <- bitwXor(d - 1L, 1L) + 1L
    if (game$state$destinations[destination, opposite] == room && game$state$keys[destination, opposite] == key) {
      game$state$locked[destination, opposite] <- locking
    }
  } else {
    item <- resolve(game, first)
    name <- game$items[[item]]$name
    key <- game$items[[item]]$key
    if (game$items[[item]]$capacity == 0L || key == 0L) fail(paste0("The ", name, " has no lock."))
    if ((game$state$containers[item] == "locked") == locking) fail(paste0("The ", name, " is ", status, "."))
    if (locking && game$state$containers[item] == "open") fail(paste0("You must close the ", name, " first."))
    key_check(game, key, second)
    game$state$containers[item] <- if (locking) "locked" else "closed"
  }
  say(if (locking) "Locked." else "Unlocked.")
}
examine <- function(game, item) {
  value <- game$items[[item]]
  say(if (length(value$details)) value$details else paste0("You see nothing special about the ", value$name, "."))
  if (value$light) say(sprintf("It is %s (fuel %d).", if (game$state$lit[item]) "lit" else "unlit", game$state$fuel[item]))
  if (value$capacity > 0L) {
    state <- game$state$containers[item]
    if (state != "open") say(paste0("It is ", state, ".")) else if (length(direct(game, inside(game, item)))) {
      say("It contains:"); item_tree(game, inside(game, item), 1L)
    } else say("It is empty.")
  }
  if (value$treasure > 0L) say(sprintf("It is a treasure worth %d points.", value$treasure))
  say(sprintf("It weighs %d.", total_weight(game, item)))
}

execute <- function(game, verb, first, second, d) {
  baseline <- is_lit(game)
  success <- TRUE
  switch(verb,
    go = {
      destination <- game$state$destinations[game$state$room, d]
      if (destination == 0L) fail("You can't go that way.")
      if (game$state$locked[game$state$room, d]) fail(paste0("The way ", directions[d], " is locked."))
      game$state$room <- destination
      baseline <- is_lit(game)
      describe(game, game$verbose || !game$state$visited[destination])
      game$state$visited[destination] <- TRUE
      run_rules(game, "enter", destination)
    },
    look = describe(game, TRUE),
    examine = examine(game, resolve(game, first)),
    take = success <- take_items(game, first, second),
    drop = drop_items(game, first),
    put = success <- put_items(game, first, second),
    inventory = {
      if (!length(direct(game, player))) say("You are empty-handed.") else {
        say("You are carrying:"); item_tree(game, player, 1L)
        say(sprintf("Total weight: %d/%d", place_weight(game, player), game$max_weight))
      }
    },
    open = {
      item <- resolve(game, first)
      name <- game$items[[item]]$name
      if (game$items[[item]]$capacity == 0L) fail(paste0("You can't open the ", name, "."))
      if (game$state$containers[item] == "open") fail(paste0("The ", name, " is already open."))
      if (game$state$containers[item] == "locked") fail(paste0("The ", name, " is locked."))
      game$state$containers[item] <- "open"
      children <- direct(game, inside(game, item))
      say(if (length(children)) paste0("Opening the ", name, " reveals ", item_names(game, children), ".") else "Opened.")
    },
    close = {
      item <- resolve(game, first)
      name <- game$items[[item]]$name
      if (game$items[[item]]$capacity == 0L) fail(paste0("You can't close the ", name, "."))
      if (game$state$containers[item] != "open") fail(paste0("The ", name, " is already closed."))
      game$state$containers[item] <- "closed"
      say("Closed.")
    },
    lock = , unlock = change_lock(game, first, second, verb == "lock"),
    use = {
      first_item <- resolve(game, first)
      second_item <- resolve(game, second)
      if (!carried(game, first_item)) fail(paste0("You aren't carrying the ", game$items[[first_item]]$name, "."))
      result <- run_rules(game, "use", first_item, second_item)
      if (result$executed == 0L) fail("Nothing happens.")
      if (!result$message) say("Done.")
    },
    light = , extinguish = {
      item <- resolve(game, first)
      name <- game$items[[item]]$name
      lighting <- verb == "light"
      if (!game$items[[item]]$light) fail(paste0("You can't ", verb, " the ", name, "."))
      if (game$state$lit[item] == lighting) fail(paste0("The ", name, " is ", if (lighting) "already lit" else "not lit", "."))
      if (lighting && game$state$fuel[item] == 0L) fail(paste0("The ", name, " has no fuel."))
      game$state$lit[item] <- lighting
      say(paste0("The ", name, " is now ", if (lighting) "lit" else "out", "."))
    },
    wait = say("Time passes."),
    score = {
      treasure <- treasures(game)
      say(sprintf("You have scored %d points (treasure %d, bonus %d) in %d moves.",
                  treasure$points + game$state$bonus, treasure$points, game$state$bonus, game$state$moves))
      say(sprintf("Treasures stored: %d of %d.", treasure$stored, treasure$total))
    },
    save = { game$saved <- game$state; say("Game saved.") },
    restore = {
      if (is.null(game$saved)) fail("There is no saved game.")
      game$state <- game$saved
      say("Game restored."); describe(game, TRUE)
    },
    verbose = { game$verbose <- TRUE; say("Verbose mode.") },
    brief = { game$verbose <- FALSE; say("Brief mode.") })
  if (success && verb %in% actions) pass_turn(game, baseline)
  invisible(NULL)
}
interpret <- function(game, tokens) {
  if (!length(tokens)) fail("I beg your pardon?")
  if (direction(tokens[1L]) != 0L) tokens <- c("go", tokens)
  verb <- unname(verbs[tokens[1L]])
  if (is.na(verb)) fail(paste0('I don\'t know the verb "', tokens[1L], '".'))
  if (game$state$ended != "none" && verb != "restore") fail("The game is over.")
  first <- after(tokens, 1L)
  second <- character()
  d <- 0L
  if (verb == "look" && length(first)) {
    if (first[1L] != "at") fail("I don't understand that.")
    verb <- "examine"
    first <- after(first, 1L)
  }
  if (verb %in% no_arguments) {
    if (length(first)) fail("I don't understand that.")
  } else {
    if (!length(first)) fail(if (verb == "go") "Which way do you want to go?" else paste0("What do you want to ", verb, "?"))
    if (verb == "go") {
      if (length(first) == 1L) d <- direction(first)
      if (d == 0L) fail("I don't understand that.")
    } else {
      prepositions <- switch(verb, put = c("in", "into"), use = c("on", "with"), lock = "with", unlock = "with", take = "from", character())
      split <- which(first %in% prepositions)
      if (length(split)) {
        index <- split[1L]
        if (index == 1L || index == length(first)) fail("I don't understand that.")
        second <- after(first, index)
        first <- head(first, index - 1L)
      } else if (verb %in% c("put", "use")) fail("I don't understand that.")
    }
  }
  execute(game, verb, first, second, d)
}
process_line <- function(game, line) {
  say(paste0("> ", line))
  tryCatch({
    tokens <- command_words(line)
    if (length(tokens) && tokens[1L] %in% c("again", "g")) {
      if (length(tokens) != 1L) fail("I don't understand that.")
      if (is.null(game$previous)) fail("There is nothing to repeat.")
      tokens <- command_words(game$previous)
    } else game$previous <- line
    interpret(game, tokens)
  }, adventure_error = function(error) say(conditionMessage(error)))
}

lines <- readLines(file("stdin"), warn = FALSE)
begin <- match("BEGIN", lines)
definitions <- lapply(lines[seq_len(begin - 1L)], function(line) strsplit(line, " ", fixed = TRUE)[[1L]])
game <- new_game(definitions)
describe(game, TRUE)
for (line in lines[seq.int(begin + 1L, length(lines))]) {
  if (line == "QUIT") break
  process_line(game, line)
}
say(sprintf("Final score: %d points in %d moves.", score(game), game$state$moves))
