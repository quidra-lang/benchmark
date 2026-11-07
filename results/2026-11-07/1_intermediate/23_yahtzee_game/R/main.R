suppressPackageStartupMessages(library(gmp))

categories <- c("ONES", "TWOS", "THREES", "FOURS", "FIVES", "SIXES", "THREEKIND",
                "FOURKIND", "FULLHOUSE", "SMALL", "LARGE", "YAHTZEE", "CHANCE")
strategies <- c("KIND", "STRAIGHT", "HIGH", "UPPER")
commands <- c("RULE", "GAME", "BOT", "LOAD", "ROLL", "HOLD", "KEEP", "SCORE", "WHATIF",
              "UNDO", "REDO", "SUGGEST", "ODDS", "ADVISE", "AUTO", "STATUS", "CARD",
              "BONUS", "STATS", "LOG", "FACES", "STANDINGS", "END", "RECORDS", "SIM")
zero <- as.bigz(0L)

emit <- function(...) cat(paste(..., sep = " "), "\n", sep = "")
fail <- function(reason) {
  stop(structure(list(message = reason, call = NULL),
                 class = c("command_error", "error", "condition")))
}

integer_word <- function(text, minimum, maximum) {
  if (!grepl("^-?(0|[1-9][0-9]*)$", text, perl = TRUE) || text == "-0") fail(paste("bad value", text))
  value <- as.bigz(text)
  if (value < minimum || value > maximum) fail(paste("bad value", text))
  as.integer(as.character(value))
}

player_name <- function(text) {
  if (!grepl("^[A-Z]{1,8}$", text, perl = TRUE)) fail(paste("bad name", text))
  text
}

strategy_word <- function(text) {
  if (!text %in% strategies) fail(paste("bad strategy", text))
  text
}

category_word <- function(text) {
  index <- match(text, categories)
  if (is.na(index)) fail(paste("bad category", text))
  index
}

hold_pattern <- function(text) {
  if (!grepl("^[01]{5}$", text)) fail(paste("bad pattern", text))
  strsplit(text, "", fixed = TRUE)[[1L]] == "1"
}

face_words <- function(tokens) vapply(tokens, integer_word, integer(1L), minimum = 1L, maximum = 6L)

fraction <- function(numerator, denominator) {
  numerator <- as.bigz(numerator)
  denominator <- as.bigz(denominator)
  divisor <- gcd.bigz(numerator, denominator)
  numerator <- numerator %/% divisor
  denominator <- denominator %/% divisor
  if (denominator == 1L) as.character(numerator) else paste0(as.character(numerator), "/", as.character(denominator))
}

average <- function(total, count) {
  value <- if (count == 0L) zero else (as.bigz(total) * 100L) %/% count
  paste0(as.character(value %/% 100L), ".", sprintf("%02d", as.integer(as.character(value %% 100L))))
}

faces_text <- function(dice) if (length(dice)) paste(dice, collapse = " ") else "-"
pattern_text <- function(holds) paste(as.integer(holds), collapse = "")
face_counts <- function(dice) tabulate(dice, nbins = 6L)
most_frequent <- function(counts) tail(which(counts == max(counts)), 1L)

candidates <- function(card, counts, joker_rule) {
  allowed <- card < 0L
  joker <- joker_rule != "OFF" && any(counts == 5L) && card[12L] >= 0L
  requirement <- ""
  if (joker && joker_rule == "FORCED") {
    face <- most_frequent(counts)
    if (card[face] < 0L) {
      allowed[] <- FALSE
      allowed[face] <- TRUE
      requirement <- categories[face]
    } else if (any(allowed[7:13])) {
      allowed[1:6] <- FALSE
      requirement <- "lower box"
    }
  }
  upper <- seq_len(6L) * counts
  total <- sum(upper)
  maximum <- max(counts)
  small <- any(vapply(1:3, function(start) all(counts[start:(start + 3L)] > 0L), logical(1L)))
  large <- any(vapply(1:2, function(start) all(counts[start:(start + 4L)] > 0L), logical(1L)))
  points <- c(upper, if (maximum >= 3L) total else 0L, if (maximum >= 4L) total else 0L,
              if (any(counts == 3L) && any(counts == 2L)) 25L else 0L,
              if (small) 30L else 0L, if (large) 40L else 0L,
              if (maximum == 5L) 50L else 0L, total)
  if (joker) points[9:11] <- c(25L, 30L, 40L)
  points[!allowed] <- 0L
  open <- which(card < 0L)
  list(allowed = allowed, points = points, best = open[which.max(points[open])],
       joker = joker, requirement = requirement)
}

new_turn <- function(player) list(player = player, rolls = 0L, dice = integer(), holds = rep(FALSE, 5L))
new_game <- function(seed, names, rules, bots = rep("KIND", length(names)), silent = FALSE) {
  list(names = names, bots = bots, rules = rules, cards = matrix(-1L, length(names), 13L),
       ybonus = integer(length(names)), turn = new_turn(1L), state = as.bigz(seed),
       loaded = integer(), loaded_head = 1L, face_totals = integer(6L),
       entries = list(), redo = list(), silent = silent)
}

upper_subtotals <- function(game) as.integer(rowSums(pmax(game$cards[, 1:6, drop = FALSE], 0L)))
player_totals <- function(game) {
  as.integer(rowSums(pmax(game$cards, 0L))) + 35L * (upper_subtotals(game) >= 63L) + game$ybonus
}
ranking <- function(game) order(-player_totals(game), seq_along(game$names), method = "radix")
player_round <- function(game, player) sum(game$cards[player, ] >= 0L) + 1L
game_emit <- function(game, ...) if (!game$silent) emit(...)

require_game <- function(app) {
  if (is.null(app$game)) fail("no game")
  app$game
}
turn_check <- function(game) if (game$turn$player == 0L) fail("game over")
rolled_check <- function(game) {
  turn_check(game)
  if (game$turn$rolls == 0L) fail("not rolled")
}
rolls_left_check <- function(game) {
  rolled_check(game)
  if (game$turn$rolls == game$rules$rolls) fail("no rolls left")
}
turn_text <- function(game) {
  player <- game$turn$player
  if (player == 0L) "game over" else paste("turn", player_round(game, player), game$names[player])
}

roll_dice <- function(game) {
  if (game$turn$rolls == 0L) game$turn$dice <- integer(5L)
  for (die in which(!game$turn$holds)) {
    if (game$loaded_head <= length(game$loaded)) {
      face <- game$loaded[game$loaded_head]
      game$loaded_head <- game$loaded_head + 1L
    } else {
      game$state <- (game$state * 48271L) %% 2147483647L
      face <- as.integer(as.character(game$state %% 6L)) + 1L
    }
    game$turn$dice[die] <- face
    game$face_totals[face] <- game$face_totals[face] + 1L
  }
  game$turn$rolls <- game$turn$rolls + 1L
  game$redo <- list()
  game_emit(game, game$names[game$turn$player], "roll", paste0(game$turn$rolls, ":"), faces_text(game$turn$dice))
  game
}

set_holds <- function(game, holds) {
  game$turn$holds <- holds
  game$redo <- list()
  game_emit(game, game$names[game$turn$player], "holds", paste0(pattern_text(holds), ":"),
            faces_text(game$turn$dice[holds]))
  game
}

score_details <- function(game, category) {
  player <- game$turn$player
  counts <- face_counts(game$turn$dice)
  options <- candidates(game$cards[player, ], counts, game$rules$joker)
  bonus <- if (any(counts == 5L) && game$cards[player, 12L] == 50L) 100L else 0L
  list(turn = game$turn, category = category, points = options$points[category],
       ybonus = bonus, joker = options$joker)
}

score_check <- function(game, category) {
  rolled_check(game)
  card <- game$cards[game$turn$player, ]
  if (card[category] >= 0L) fail(paste(categories[category], "already used"))
  options <- candidates(card, face_counts(game$turn$dice), game$rules$joker)
  if (!options$allowed[category]) fail(paste("joker requires", options$requirement))
}

score_text <- function(game, entry, hypothetical = FALSE) {
  player <- entry$turn$player
  upper <- upper_subtotals(game)[player]
  after <- upper + (if (entry$category <= 6L) entry$points else 0L)
  added <- if (upper < 63L && after >= 63L) 35L else 0L
  text <- paste(game$names[player], if (hypothetical) "would score" else "scores",
                entry$points, "in", categories[entry$category])
  if (entry$joker) text <- paste(text, "joker")
  if (entry$ybonus) text <- paste(text, "ybonus 100")
  if (added) text <- paste(text, "ubonus 35")
  paste(text, "total", player_totals(game)[player] + entry$points + entry$ybonus + added)
}

enter_score <- function(game, category) {
  entry <- score_details(game, category)
  game_emit(game, score_text(game, entry))
  player <- entry$turn$player
  game$cards[player, category] <- entry$points
  game$ybonus[player] <- game$ybonus[player] + entry$ybonus
  game$entries[[length(game$entries) + 1L]] <- entry
  game$redo <- list()
  next_player <- if (length(game$entries) == 13L * length(game$names)) 0L else player %% length(game$names) + 1L
  game$turn <- new_turn(next_player)
  game_emit(game, turn_text(game))
  game
}

bot_holds <- function(strategy, dice) {
  if (strategy == "HIGH") return(dice >= 5L)
  counts <- face_counts(dice)
  if (strategy == "STRAIGHT") {
    best_start <- best_length <- 0L
    for (start in seq_len(6L)) {
      run <- 0L
      while (start + run <= 6L && counts[start + run] > 0L) run <- run + 1L
      if (run >= best_length) {
        best_start <- start
        best_length <- run
      }
    }
    if (best_length >= 3L) {
      holds <- rep(FALSE, 5L)
      holds[match(seq.int(best_start, length.out = best_length), dice)] <- TRUE
      return(holds)
    }
  }
  dice == most_frequent(counts)
}

bot_turn <- function(game) {
  if (game$turn$rolls == 0L) game <- roll_dice(game)
  strategy <- game$bots[game$turn$player]
  while (game$turn$rolls < game$rules$rolls) {
    holds <- bot_holds(strategy, game$turn$dice)
    if (all(holds)) break
    game <- roll_dice(set_holds(game, holds))
  }
  counts <- face_counts(game$turn$dice)
  options <- candidates(game$cards[game$turn$player, ], counts, game$rules$joker)
  face <- most_frequent(counts)
  category <- if (strategy == "UPPER" && counts[face] >= 3L && options$allowed[face]) face else options$best
  enter_score(game, category)
}

compositions <- function(total, faces = 6L) {
  if (faces == 1L) return(matrix(total, 1L, 1L))
  rows <- lapply(seq.int(0L, total), function(count) {
    suffix <- compositions(total - count, faces - 1L)
    cbind(count, suffix)
  })
  do.call(rbind, rows)
}
count_key <- function(counts) sum(counts * c(7776L, 1296L, 216L, 36L, 6L, 1L)) + 1L

make_tables <- function() {
  outcomes <- lapply(0:5, function(total) {
    counts <- compositions(total)
    weights <- c_bigz(lapply(seq_len(nrow(counts)), function(row) {
      factorialZ(total) %/% prod(factorialZ(counts[row, ]))
    }))
    list(counts = counts, weights = weights)
  })
  full <- outcomes[[6L]]$counts
  held <- do.call(rbind, lapply(outcomes, `[[`, "counts"))
  full_lookup <- held_lookup <- rep(NA_integer_, 46656L)
  full_lookup[vapply(seq_len(nrow(full)), function(row) count_key(full[row, ]), integer(1L))] <- seq_len(nrow(full))
  held_lookup[vapply(seq_len(nrow(held)), function(row) count_key(held[row, ]), integer(1L))] <- seq_len(nrow(held))
  next_states <- weights <- vector("list", nrow(held))
  for (row in seq_len(nrow(held))) {
    kept <- sum(held[row, ])
    rolled <- outcomes[[6L - kept]]
    next_states[[row]] <- vapply(seq_len(nrow(rolled$counts)), function(index) {
      full_lookup[count_key(held[row, ] + rolled$counts[index, ])]
    }, integer(1L))
    weights[[row]] <- rolled$weights * as.bigz(6L)^kept
  }
  subsets <- lapply(seq_len(nrow(full)), function(row) {
    which(rowSums(sweep(held, 2L, full[row, ], FUN = `<=`)) == 6L)
  })
  patterns <- t(vapply(0:31, function(mask) {
    bitwAnd(mask, c(16L, 8L, 4L, 2L, 1L)) != 0L
  }, logical(5L)))
  list(outcomes = outcomes, full = full, held = held, held_lookup = held_lookup,
       next_states = next_states, weights = weights, subsets = subsets, patterns = patterns)
}

print_odds <- function(game, tables, holds) {
  held <- face_counts(game$turn$dice[holds])
  rolled <- 5L - sum(held)
  distribution <- tables$outcomes[[rolled + 1L]]
  denominator <- as.bigz(6L)^rolled
  totals <- chances <- rep(zero, 13L)
  best_total <- zero
  card <- game$cards[game$turn$player, ]
  for (row in seq_len(nrow(distribution$counts))) {
    options <- candidates(card, held + distribution$counts[row, ], game$rules$joker)
    weight <- distribution$weights[row]
    totals <- totals + as.bigz(options$points) * weight
    chances <- chances + as.bigz(as.integer(options$points > 0L)) * weight
    best_total <- best_total + weight * options$points[options$best]
  }
  emit("odds", pattern_text(holds), "outcomes", as.character(denominator))
  for (category in which(card < 0L)) {
    emit(categories[category], "expect", fraction(totals[category], denominator),
         "chance", fraction(chances[category], denominator))
  }
  emit("best expect", fraction(best_total, denominator))
}

print_advice <- function(game, tables) {
  card <- game$cards[game$turn$player, ]
  values <- as.bigz(vapply(seq_len(nrow(tables$full)), function(row) {
    options <- candidates(card, tables$full[row, ], game$rules$joker)
    as.integer(options$points[options$best])
  }, integer(1L)))
  remaining <- game$rules$rolls - game$turn$rolls
  expected <- rep(zero, nrow(tables$held))
  for (depth in seq_len(remaining)) {
    for (index in seq_len(nrow(tables$held))) {
      expected[index] <- sum(tables$weights[[index]] * values[tables$next_states[[index]]])
    }
    if (depth < remaining) {
      for (row in seq_len(nrow(tables$full))) values[row] <- max(expected[tables$subsets[[row]]])
    }
  }
  choices <- rep(zero, 32L)
  for (index in seq_len(32L)) {
    held <- face_counts(game$turn$dice[tables$patterns[index, ]])
    choices[index] <- expected[tables$held_lookup[count_key(held)]]
  }
  index <- which.max(choices)
  holds <- tables$patterns[index, ]
  emit("advise", paste0(pattern_text(holds), ":"), faces_text(game$turn$dice[holds]),
       "expect", fraction(choices[index], as.bigz(7776L)^remaining))
}

card_row <- function(heading, names, cells) {
  widths <- pmax(4L, nchar(names, type = "bytes"))
  emit(paste0(sprintf("%-9s", heading), " ", paste(sprintf("%*s", widths, cells), collapse = " ")))
}

print_card <- function(game) {
  card_row("CATEGORY", game$names, game$names)
  for (category in seq_len(13L)) {
    points <- game$cards[, category]
    card_row(categories[category], game$names, ifelse(points < 0L, "-", as.character(points)))
  }
  upper <- upper_subtotals(game)
  card_row("UPPER", game$names, as.character(upper))
  card_row("BONUS", game$names, as.character(35L * (upper >= 63L)))
  card_row("YBONUS", game$names, as.character(game$ybonus))
  card_row("TOTAL", game$names, as.character(player_totals(game)))
}

print_stats <- function(game) {
  for (player in seq_along(game$names)) {
    entries <- Filter(function(entry) entry$turn$player == player, game$entries)
    points <- vapply(entries, `[[`, integer(1L), "points")
    rolls <- sum(vapply(entries, function(entry) entry$turn$rolls, integer(1L)))
    yahtzees <- sum(vapply(entries, function(entry) any(face_counts(entry$turn$dice) == 5L), logical(1L)))
    emit("stats", game$names[player], "turns", length(entries), "rolls", rolls,
         "zeros", sum(points == 0L), "yahtzees", yahtzees, "average", average(sum(points), length(entries)))
  }
}

record_game <- function(records, game) {
  totals <- player_totals(game)
  winner <- ranking(game)[1L]
  for (player in seq_along(game$names)) {
    name <- game$names[player]
    record <- records[[name]]
    if (is.null(record)) record <- list(games = 0L, wins = 0L, best = 0L, total = 0L)
    record$games <- record$games + 1L
    record$wins <- record$wins + as.integer(player == winner)
    record$best <- max(record$best, totals[player])
    record$total <- record$total + totals[player]
    records[[name]] <- record
  }
  records
}

print_records <- function(records) {
  if (!length(records)) {
    emit("no records")
    return(invisible(NULL))
  }
  names <- names(records)
  wins <- vapply(records, `[[`, integer(1L), "wins")
  best <- vapply(records, `[[`, integer(1L), "best")
  for (index in order(-wins, -best, names, method = "radix")) {
    record <- records[[index]]
    emit("record", names[index], "games", record$games, "wins", record$wins, "best", record$best,
         "average", average(record$total, record$games))
  }
}

simulate <- function(seed, count, bots, rules) {
  seats <- seq_along(bots)
  totals <- matrix(0L, length(bots), 5L)
  generator <- as.bigz(seed)
  for (game_number in seq_len(count)) {
    game <- new_game(generator, LETTERS[seats], rules, bots, TRUE)
    while (game$turn$player != 0L) game <- bot_turn(game)
    generator <- game$state
    scores <- player_totals(game)
    winner <- ranking(game)[1L]
    totals[, 1L] <- totals[, 1L] + as.integer(seats == winner)
    totals[, 2L] <- totals[, 2L] + scores
    totals[, 3L] <- pmax(totals[, 3L], scores)
    totals[, 4L] <- totals[, 4L] + as.integer(upper_subtotals(game) >= 63L)
    totals[, 5L] <- totals[, 5L] + as.integer(game$cards[, 12L] == 50L)
  }
  emit("sim seed", seed, "games", count, "players", length(bots))
  for (seat in seats) {
    emit("seat", seat, bots[seat], "wins", totals[seat, 1L], "average", average(totals[seat, 2L], count),
         "best", totals[seat, 3L], "bonus", totals[seat, 4L], "yahtzee", totals[seat, 5L])
  }
}

game_command <- function(app, tokens) {
  op <- tokens[1L]
  if (op == "BOT") {
    name <- player_name(tokens[2L])
    strategy <- strategy_word(tokens[3L])
  } else if (op %in% c("LOAD", "KEEP")) {
    faces <- face_words(tokens[-1L])
  } else if (op %in% c("HOLD", "ODDS")) {
    holds <- hold_pattern(tokens[2L])
  } else if (op %in% c("SCORE", "WHATIF")) {
    category <- category_word(tokens[2L])
  } else if (op == "AUTO") {
    count <- integer_word(tokens[2L], 1L, 100L)
  }
  game <- require_game(app)
  if (op == "BOT") {
    player <- match(name, game$names)
    if (is.na(player)) fail(paste("no player", name))
    game$bots[player] <- strategy
    emit("bot", name, strategy)
  } else if (op == "LOAD") {
    game$loaded <- c(game$loaded, faces)
    emit("loaded", length(game$loaded) - game$loaded_head + 1L)
  } else if (op == "ROLL") {
    turn_check(game)
    if (game$turn$rolls == game$rules$rolls) fail("no rolls left")
    if (all(game$turn$holds)) fail("all dice held")
    game <- roll_dice(game)
  } else if (op == "HOLD") {
    rolls_left_check(game)
    game <- set_holds(game, holds)
  } else if (op == "KEEP") {
    rolls_left_check(game)
    holds <- rep(FALSE, 5L)
    for (face in faces) {
      available <- which(!holds & game$turn$dice == face)
      if (!length(available)) fail(paste("not showing", face))
      holds[available[1L]] <- TRUE
    }
    game <- set_holds(game, holds)
  } else if (op %in% c("SCORE", "WHATIF")) {
    score_check(game, category)
    if (op == "WHATIF") {
      emit(score_text(game, score_details(game, category), TRUE))
    } else game <- enter_score(game, category)
  } else if (op == "UNDO") {
    if (!length(game$entries)) fail("nothing to undo")
    entry <- game$entries[[length(game$entries)]]
    game$redo[[length(game$redo) + 1L]] <- list(resume = game$turn, entry = entry)
    game$entries <- game$entries[-length(game$entries)]
    game$cards[entry$turn$player, entry$category] <- -1L
    game$ybonus[entry$turn$player] <- game$ybonus[entry$turn$player] - entry$ybonus
    game$turn <- entry$turn
    emit("undo", game$names[entry$turn$player], categories[entry$category], entry$points)
  } else if (op == "REDO") {
    if (!length(game$redo)) fail("nothing to redo")
    saved <- game$redo[[length(game$redo)]]
    game$redo <- game$redo[-length(game$redo)]
    entry <- saved$entry
    game$cards[entry$turn$player, entry$category] <- entry$points
    game$ybonus[entry$turn$player] <- game$ybonus[entry$turn$player] + entry$ybonus
    game$entries[[length(game$entries) + 1L]] <- entry
    game$turn <- saved$resume
    emit("redo", game$names[entry$turn$player], categories[entry$category], entry$points)
  } else if (op == "SUGGEST") {
    rolled_check(game)
    card <- game$cards[game$turn$player, ]
    options <- candidates(card, face_counts(game$turn$dice), game$rules$joker)
    open <- which(card < 0L)
    emit("suggest", paste(categories[open], options$points[open], collapse = " "),
         "best", categories[options$best], options$points[options$best])
  } else if (op == "ODDS") {
    rolls_left_check(game)
    print_odds(game, app$tables, holds)
  } else if (op == "ADVISE") {
    rolls_left_check(game)
    print_advice(game, app$tables)
  } else if (op == "AUTO") {
    turn_check(game)
    game$redo <- list()
    for (iteration in seq_len(count)) {
      if (game$turn$player == 0L) break
      game <- bot_turn(game)
    }
  } else if (op == "STATUS") {
    player <- game$turn$player
    if (player == 0L) {
      emit("status game over")
    } else {
      emit("status round", player_round(game, player), "player", game$names[player],
           "rolls", game$turn$rolls, "dice", faces_text(game$turn$dice), "holds", pattern_text(game$turn$holds))
    }
  } else if (op == "CARD") {
    print_card(game)
  } else if (op == "BONUS") {
    upper <- upper_subtotals(game)
    for (player in seq_along(game$names)) {
      maximum <- upper[player] + sum(5L * (1:6)[game$cards[player, 1:6] < 0L])
      status <- if (upper[player] >= 63L) "made" else if (maximum < 63L) "lost" else "open"
      emit("bonus", game$names[player], "upper", upper[player], "need", max(63L - upper[player], 0L),
           "max", maximum, status)
    }
  } else if (op == "STATS") {
    print_stats(game)
  } else if (op == "LOG") {
    if (!length(game$entries)) emit("no scores")
    for (index in seq_along(game$entries)) {
      entry <- game$entries[[index]]
      text <- paste("log", index, game$names[entry$turn$player], faces_text(entry$turn$dice),
                    categories[entry$category], entry$points)
      if (entry$joker) text <- paste(text, "joker")
      if (entry$ybonus) text <- paste(text, "ybonus 100")
      emit(text)
    }
  } else if (op == "FACES") {
    counts <- as.bigz(game$face_totals)
    total <- sum(counts)
    chi <- if (total == 0L) "0" else fraction(6L * sum(counts * counts) - total * total, total)
    emit("faces", faces_text(game$face_totals), "total", as.character(total), "chi2", chi)
  } else if (op %in% c("STANDINGS", "END")) {
    order <- ranking(game)
    totals <- player_totals(game)
    finished <- game$turn$player == 0L
    if (op == "END") emit("end", if (finished) "final" else "abandoned")
    for (rank in seq_along(order)) {
      player <- order[rank]
      if (op == "STANDINGS") {
        emit("standing", rank, game$names[player], totals[player], "behind", totals[order[1L]] - totals[player])
      } else emit("rank", rank, game$names[player], totals[player])
    }
    if (op == "END") {
      if (finished) app$records <- record_game(app$records, game)
      app$game <- NULL
      return(invisible(NULL))
    }
  }
  app$game <- game
  invisible(NULL)
}

execute <- function(app, tokens) {
  op <- tokens[1L]
  if (!op %in% commands) fail(paste("unknown command", op))
  if (op == "RULE") {
    rule <- tokens[2L]
    value <- tokens[3L]
    if (!rule %in% c("ROLLS", "JOKER")) fail(paste("unknown rule", rule))
    changed <- app$rules
    if (rule == "ROLLS") {
      changed$rolls <- integer_word(value, 1L, 4L)
    } else {
      if (!value %in% c("FORCED", "FREE", "OFF")) fail(paste("bad value", value))
      changed$joker <- value
    }
    if (!is.null(app$game)) fail("game in progress")
    app$rules <- changed
    emit("rule", rule, value)
  } else if (op == "GAME") {
    seed <- integer_word(tokens[2L], 1L, 2147483646L)
    names <- tokens[-c(1L, 2L)]
    for (name in names) player_name(name)
    if (length(names) > 6L) fail("too many players")
    if (!is.null(app$game)) fail("game in progress")
    duplicates <- which(duplicated(names))
    if (length(duplicates)) fail(paste("duplicate name", names[duplicates[1L]]))
    app$game <- new_game(seed, names, app$rules)
    emit("game seed", seed, "players", paste(names, collapse = " "))
    emit("turn 1", names[1L])
  } else if (op == "RECORDS") {
    print_records(app$records)
  } else if (op == "SIM") {
    seed <- integer_word(tokens[2L], 1L, 2147483646L)
    count <- integer_word(tokens[3L], 1L, 50L)
    bots <- vapply(tokens[-c(1L, 2L, 3L)], strategy_word, character(1L))
    if (length(bots) > 6L) fail("too many players")
    simulate(seed, count, bots, app$rules)
  } else game_command(app, tokens)
  invisible(NULL)
}

input <- file("stdin", open = "r")
command_count <- as.integer(readLines(input, n = 1L, warn = FALSE))
app <- new.env(parent = emptyenv())
app$rules <- list(rolls = 3L, joker = "FORCED")
app$game <- NULL
app$records <- list()
app$tables <- make_tables()
for (command_number in seq_len(command_count)) {
  tokens <- strsplit(readLines(input, n = 1L, warn = FALSE), " ", fixed = TRUE)[[1L]]
  tryCatch(execute(app, tokens), command_error = function(problem) emit("error:", conditionMessage(problem)))
}
close(input)
