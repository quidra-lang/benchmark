rally_sports <- c("TENNIS", "TABLETENNIS", "BADMINTON", "VOLLEYBALL")
option_rules <- list(
  TENNIS = list(SETS = c("3", "5"), DEUCE = c("AD", "NOAD"), FINAL = c("TB7", "TB10", "ADV", "SUPER"), FIRST = c("A", "B")),
  TABLETENNIS = list(GAMES = c("5", "7"), FIRST = c("A", "B")),
  BADMINTON = list(FIRST = c("A", "B")), VOLLEYBALL = list(FIRST = c("A", "B")),
  DARTS = list(START = c("501", "301", "701"), SETS = as.character(1:5), LEGS = as.character(1:5), FIRST = c("A", "B")),
  BOWLING = list()
)
score_error <- function(message) stop(message, call. = FALSE)
side <- function(text) if (text == "A") 1L else 2L
other <- function(player) 3L - player
pair_text <- function(values) paste(values, collapse = "-")

checkout_tables <- function() {
  candidates <- list()
  doubles <- list()
  darts <- new.env(hash = TRUE, parent = emptyenv())
  darts[["25"]] <- c(25L, 0L)
  darts[["BULL"]] <- c(50L, 1L)
  darts[["MISS"]] <- c(0L, 0L)
  multipliers <- c(S = 1L, T = 3L, D = 2L)
  for (prefix in names(multipliers)) {
    for (value in 20:1) {
      code <- paste0(prefix, value)
      item <- list(code = code, value = value * multipliers[[prefix]])
      candidates[[length(candidates) + 1L]] <- item
      darts[[code]] <- c(item$value, as.integer(prefix == "D"))
      if (prefix == "D") doubles[[length(doubles) + 1L]] <- item
    }
  }
  candidates <- c(candidates, list(list(code = "25", value = 25L), list(code = "BULL", value = 50L)))
  doubles[[length(doubles) + 1L]] <- list(code = "BULL", value = 50L)
  tables <- lapply(1:3, function(i) new.env(hash = TRUE, parent = emptyenv()))
  put <- function(count, total, codes) {
    key <- as.character(total)
    if (is.null(tables[[count]][[key]])) tables[[count]][[key]] <- codes
  }
  for (last in doubles) put(1L, last$value, last$code)
  for (first in candidates) {
    for (last in doubles) put(2L, first$value + last$value, c(first$code, last$code))
  }
  for (first in candidates) {
    for (second in candidates) {
      for (last in doubles) put(3L, first$value + second$value + last$value, c(first$code, second$code, last$code))
    }
  }
  list(darts = darts, tables = tables)
}
checkout_data <- checkout_tables()
checkout <- function(score, maximum = 3L) {
  if (maximum > 0L) {
    for (count in seq_len(maximum)) {
      answer <- checkout_data$tables[[count]][[as.character(score)]]
      if (!is.null(answer)) return(answer)
    }
  }
  character()
}
create_match <- function(tokens) {
  m <- new.env(parent = emptyenv())
  m$id <- tokens[2L]
  m$sport <- tokens[3L]
  m$names <- tokens[4L]
  if (m$sport != "BOWLING") m$names <- tokens[4:5]
  m$initial <- list()
  if (m$sport == "VOLLEYBALL") {
    m$initial <- lapply(tokens[6:7], function(text) as.integer(strsplit(text, ",", fixed = TRUE)[[1L]]))
    first_option <- 8L
  } else if (m$sport == "BOWLING") {
    first_option <- 5L
  } else {
    first_option <- 6L
  }
  rules <- option_rules[[m$sport]]
  m$options <- lapply(rules, function(values) values[1L])
  seen <- character()
  if (first_option <= length(tokens)) {
    for (token in tokens[first_option:length(tokens)]) {
      parts <- strsplit(paste0(token, "!"), "=", fixed = TRUE)[[1L]]
      if (length(parts) != 2L) score_error("invalid option")
      key <- parts[1L]
      value <- substr(parts[2L], 1L, nchar(parts[2L]) - 1L)
      if (is.null(rules[[key]]) || !(value %in% rules[[key]]) || key %in% seen) score_error("invalid option")
      seen <- c(seen, key)
      m$options[[key]] <- value
    }
  }
  first <- if (is.null(m$options$FIRST)) 1L else side(m$options$FIRST)
  stat_names <- c("points", "served", "servewins", "runmax", "holds", "games", "breaks", "opportunities", "converted",
                  "darts", "scored", "busts", "high", "tons", "maximums", "attempts", "hits")
  stats <- setNames(lapply(stat_names, function(key) c(0L, 0L)), stat_names)
  s <- list(p = c(0L, 0L), g = c(0L, 0L), won = c(0L, 0L), server = first, winner = 0L,
            completed = list(), stats = stats, last = 0L, run = 0L)
  if (m$sport == "VOLLEYBALL") {
    s$lineups <- m$initial
    s$subs <- c(0L, 0L)
    s$timeouts <- c(0L, 0L)
  } else if (m$sport == "BOWLING") {
    s$frames <- rep(list(integer()), 10L)
    s$marks <- rep(list(character()), 10L)
    s$frame <- 1L
    s$standing <- 10L
    s$fresh <- TRUE
  } else if (m$sport == "DARTS") {
    start <- as.integer(m$options$START)
    s$legs <- c(0L, 0L)
    s$remaining <- c(start, start)
    s$turn <- character()
    s$turnscore <- 0L
    s$turnstart <- start
    s$legnumber <- 0L
  }
  m$state <- s
  m$history <- new.env(hash = TRUE, parent = emptyenv())
  m$history_size <- 0L
  m
}
remember <- function(m, record) {
  m$history_size <- m$history_size + 1L
  m$history[[as.character(m$history_size)]] <- record
}
tennis_mode <- function(m) {
  s <- m$state
  final <- s$won[1L] == as.integer(m$options$SETS) %/% 2L && s$won[1L] == s$won[2L]
  if (final && m$options$FINAL == "SUPER") return("SUPER")
  if (all(s$g == c(6L, 6L)) && !(final && m$options$FINAL == "ADV")) return("TB")
  "NORMAL"
}
rally_server <- function(m) {
  s <- m$state
  if (m$sport == "TENNIS") {
    if (tennis_mode(m) != "NORMAL" && ((sum(s$p) + 1L) %/% 2L) %% 2L == 1L) return(other(s$server))
  } else if (m$sport == "TABLETENNIS") {
    first <- side(m$options$FIRST)
    if (length(s$completed) %% 2L == 1L) first <- other(first)
    total <- sum(s$p)
    flip <- if (total < 20L) (total %/% 2L) %% 2L == 1L else total %% 2L == 1L
    return(if (flip) other(first) else first)
  }
  s$server
}
rally_outcome <- function(m, winner) {
  s <- m$state
  points <- s$p
  points[winner] <- points[winner] + 1L
  loser <- other(winner)
  game <- FALSE
  if (m$sport == "TENNIS") {
    mode <- tennis_mode(m)
    if (mode == "NORMAL") {
      game <- points[winner] >= 4L && (m$options$DEUCE == "NOAD" || points[winner] - points[loser] >= 2L)
      games <- s$g[winner] + 1L
      unit <- game && games >= 6L && games - s$g[loser] >= 2L
    } else {
      final <- s$won[1L] == s$won[2L] && s$won[1L] == as.integer(m$options$SETS) %/% 2L
      target <- if (mode == "SUPER" || (final && m$options$FINAL == "TB10")) 10L else 7L
      unit <- points[winner] >= target && points[winner] - points[loser] >= 2L
    }
    needed <- as.integer(m$options$SETS) %/% 2L + 1L
  } else if (m$sport == "TABLETENNIS") {
    unit <- points[winner] >= 11L && points[winner] - points[loser] >= 2L
    needed <- as.integer(m$options$GAMES) %/% 2L + 1L
  } else if (m$sport == "BADMINTON") {
    unit <- points[winner] == 30L || (points[winner] >= 21L && points[winner] - points[loser] >= 2L)
    needed <- 2L
  } else {
    target <- if (length(s$completed) == 4L) 15L else 25L
    unit <- points[winner] >= target && points[winner] - points[loser] >= 2L
    needed <- 3L
  }
  c(game, unit, unit && s$won[winner] + 1L == needed)
}
point_event <- function(m, winner) {
  server <- rally_server(m)
  outcome <- rally_outcome(m, winner)
  game <- outcome[1L]
  unit <- outcome[2L]
  finished <- outcome[3L]
  mode <- if (m$sport == "TENNIS") tennis_mode(m) else ""
  opportunity <- mode == "NORMAL" && rally_outcome(m, other(server))[1L]
  s <- m$state
  record <- as.integer(c(1L, winner, server, opportunity, game, s$p, s$g, s$won, s$server,
                         length(s$completed), s$last, s$run, s$stats$runmax[winner], 0L, 0L))
  s$stats$points[winner] <- s$stats$points[winner] + 1L
  s$stats$served[server] <- s$stats$served[server] + 1L
  if (winner == server) s$stats$servewins[server] <- s$stats$servewins[server] + 1L
  s$run <- if (s$last == winner) s$run + 1L else 1L
  s$last <- winner
  s$stats$runmax[winner] <- max(s$stats$runmax[winner], s$run)
  if (opportunity) {
    s$stats$opportunities[other(server)] <- s$stats$opportunities[other(server)] + 1L
    if (winner != server) s$stats$converted[winner] <- s$stats$converted[winner] + 1L
  }
  s$p[winner] <- s$p[winner] + 1L
  if (m$sport == "TENNIS") {
    if (game) {
      s$stats$games[server] <- s$stats$games[server] + 1L
      if (winner == server) {
        s$stats$holds[winner] <- s$stats$holds[winner] + 1L
      } else {
        s$stats$breaks[winner] <- s$stats$breaks[winner] + 1L
      }
      s$g[winner] <- s$g[winner] + 1L
      s$server <- other(s$server)
    } else if (unit) {
      s$server <- other(s$server)
    }
    if (unit) {
      if (mode == "SUPER") {
        record_score <- c(s$p, 2L, 0L)
      } else if (mode == "TB") {
        s$g[winner] <- s$g[winner] + 1L
        record_score <- c(s$g, 1L, s$p[other(winner)])
      } else {
        record_score <- c(s$g, 0L, 0L)
      }
      s$completed[[length(s$completed) + 1L]] <- record_score
    }
  } else if (m$sport == "BADMINTON") {
    s$server <- winner
  } else if (m$sport == "VOLLEYBALL" && winner != server) {
    s$server <- winner
    lineup <- s$lineups[[winner]]
    s$lineups[[winner]] <- c(lineup[2:6], lineup[1L])
    record[18L] <- 1L
  }
  if (unit) {
    if (m$sport != "TENNIS") s$completed[[length(s$completed) + 1L]] <- c(s$p, 0L, 0L)
    s$won[winner] <- s$won[winner] + 1L
    if (finished) {
      s$winner <- winner
    } else {
      if (m$sport == "VOLLEYBALL") {
        record[17L] <- 1L
        record <- c(record, s$lineups[[1L]], s$lineups[[2L]], s$subs, s$timeouts)
        s$lineups <- m$initial
        s$subs <- c(0L, 0L)
        s$timeouts <- c(0L, 0L)
        first <- side(m$options$FIRST)
        s$server <- if (length(s$completed) %% 2L == 0L) first else other(first)
      }
      s$p <- c(0L, 0L)
      s$g <- c(0L, 0L)
    }
  } else if (game) {
    s$p <- c(0L, 0L)
  }
  m$state <- s
  remember(m, record)
}
roll_event <- function(s, pins) {
  if (pins > s$standing) score_error("too many pins")
  frame <- s$frame
  if (s$fresh && pins == 10L) {
    mark <- "X"
  } else if (pins == s$standing) {
    mark <- "/"
  } else {
    mark <- if (pins == 0L) "-" else as.character(pins)
  }
  s$frames[[frame]] <- c(s$frames[[frame]], pins)
  s$marks[[frame]] <- c(s$marks[[frame]], mark)
  s$standing <- s$standing - pins
  s$fresh <- FALSE
  rolls <- s$frames[[frame]]
  if (frame < 10L) {
    if ((length(rolls) == 1L && pins == 10L) || length(rolls) == 2L) {
      s$frame <- s$frame + 1L
      s$standing <- 10L
      s$fresh <- TRUE
    }
  } else {
    complete <- length(rolls) == 3L || (length(rolls) == 2L && rolls[1L] != 10L && sum(rolls) < 10L)
    if (complete) {
      s$winner <- 1L
    } else if (s$standing == 0L) {
      s$standing <- 10L
      s$fresh <- TRUE
    }
  }
  s
}
bowling_scores <- function(s) {
  scores <- rep(NA_integer_, 10L)
  for (frame in 1:10) {
    rolls <- s$frames[[frame]]
    if (!length(rolls)) next
    later <- integer()
    if (frame < 10L) later <- unlist(s$frames[(frame + 1L):10L], use.names = FALSE)
    if (frame == 10L) {
      if (s$winner != 0L) scores[frame] <- sum(rolls)
    } else if (rolls[1L] == 10L) {
      if (length(later) >= 2L) scores[frame] <- 10L + later[1L] + later[2L]
    } else if (length(rolls) == 2L) {
      if (sum(rolls) == 10L) {
        if (length(later)) scores[frame] <- 10L + later[1L]
      } else {
        scores[frame] <- sum(rolls)
      }
    }
  }
  scores
}
complete_turn <- function(s, player) {
  score <- s$turnscore
  s$stats$high[player] <- max(s$stats$high[player], score)
  if (score >= 100L) s$stats$tons[player] <- s$stats$tons[player] + 1L
  if (score == 180L) s$stats$maximums[player] <- s$stats$maximums[player] + 1L
  s
}
next_turn <- function(s) {
  s$server <- other(s$server)
  s$turn <- character()
  s$turnscore <- 0L
  s$turnstart <- s$remaining[s$server]
  s
}
dart_event <- function(m, code) {
  dart <- checkout_data$darts[[code]]
  if (is.null(dart)) score_error("invalid dart")
  s <- m$state
  player <- s$server
  value <- dart[1L]
  double <- dart[2L] == 1L
  before <- s$remaining[player]
  s$stats$darts[player] <- s$stats$darts[player] + 1L
  if (before == 50L || (before <= 40L && before %% 2L == 0L)) s$stats$attempts[player] <- s$stats$attempts[player] + 1L
  remaining <- before - value
  if (remaining < 0L || remaining == 1L || (remaining == 0L && !double)) {
    s$stats$busts[player] <- s$stats$busts[player] + 1L
    s$stats$scored[player] <- s$stats$scored[player] - s$turnscore
    s$remaining[player] <- s$turnstart
    m$state <- next_turn(s)
    return(invisible(NULL))
  }
  s$stats$scored[player] <- s$stats$scored[player] + value
  s$remaining[player] <- remaining
  s$turnscore <- s$turnscore + value
  s$turn <- c(s$turn, code)
  if (remaining == 0L) {
    s$stats$hits[player] <- s$stats$hits[player] + 1L
    s <- complete_turn(s, player)
    s$legs[player] <- s$legs[player] + 1L
    set_over <- s$legs[player] == as.integer(m$options$LEGS)
    if (set_over) {
      s$completed[[length(s$completed) + 1L]] <- c(s$legs, 0L, 0L)
      s$won[player] <- s$won[player] + 1L
    }
    if (set_over && s$won[player] == as.integer(m$options$SETS)) {
      s$winner <- player
      m$state <- s
      return(invisible(NULL))
    }
    if (set_over) s$legs <- c(0L, 0L)
    s$legnumber <- s$legnumber + 1L
    first <- side(m$options$FIRST)
    s$server <- if (s$legnumber %% 2L == 0L) first else other(first)
    start <- as.integer(m$options$START)
    s$remaining <- c(start, start)
    s$turn <- character()
    s$turnscore <- 0L
    s$turnstart <- start
  } else if (length(s$turn) == 3L) {
    s <- next_turn(complete_turn(s, player))
  }
  m$state <- s
}
undo_event <- function(m) {
  if (m$history_size == 0L) score_error("nothing to undo")
  key <- as.character(m$history_size)
  data <- m$history[[key]]
  rm(list = key, envir = m$history)
  m$history_size <- m$history_size - 1L
  if (is.list(data)) {
    m$state <- data
    return(invisible(NULL))
  }
  s <- m$state
  if (data[1L] == 2L) {
    s$lineups[[data[2L]]][data[3L]] <- data[4L]
    s$subs[data[2L]] <- s$subs[data[2L]] - 1L
  } else if (data[1L] == 3L) {
    s$timeouts[data[2L]] <- s$timeouts[data[2L]] - 1L
  } else {
    winner <- data[2L]
    server <- data[3L]
    s$stats$points[winner] <- s$stats$points[winner] - 1L
    s$stats$served[server] <- s$stats$served[server] - 1L
    if (winner == server) s$stats$servewins[server] <- s$stats$servewins[server] - 1L
    if (data[4L] == 1L) {
      s$stats$opportunities[other(server)] <- s$stats$opportunities[other(server)] - 1L
      if (winner != server) s$stats$converted[winner] <- s$stats$converted[winner] - 1L
    }
    if (data[5L] == 1L) {
      s$stats$games[server] <- s$stats$games[server] - 1L
      if (winner == server) {
        s$stats$holds[winner] <- s$stats$holds[winner] - 1L
      } else {
        s$stats$breaks[winner] <- s$stats$breaks[winner] - 1L
      }
    }
    if (data[17L] == 1L) {
      s$lineups <- list(data[19:24], data[25:30])
      s$subs <- data[31:32]
      s$timeouts <- data[33:34]
    }
    if (data[18L] == 1L) {
      lineup <- s$lineups[[winner]]
      s$lineups[[winner]] <- c(lineup[6L], lineup[1:5])
    }
    s$p <- data[6:7]
    s$g <- data[8:9]
    s$won <- data[10:11]
    s$server <- data[12L]
    s$winner <- 0L
    s$completed <- s$completed[seq_len(data[13L])]
    s$last <- data[14L]
    s$run <- data[15L]
    s$stats$runmax[winner] <- data[16L]
  }
  m$state <- s
}
event <- function(m, command, args) {
  correct <- (command == "POINT" && m$sport %in% rally_sports) || (command == "ROLL" && m$sport == "BOWLING") ||
    (command == "THROW" && m$sport == "DARTS") || (command %in% c("SUB", "TIMEOUT") && m$sport == "VOLLEYBALL")
  if (!correct) score_error("wrong event")
  if (command == "POINT") {
    events <- strsplit(args[1L], "", fixed = TRUE)[[1L]]
  } else if (command %in% c("SUB", "TIMEOUT")) {
    events <- ""
  } else {
    events <- args
  }
  for (value in events) {
    if (m$state$winner != 0L) score_error("match over")
    if (command == "POINT") {
      point_event(m, side(value))
    } else if (command == "ROLL") {
      old <- m$state
      m$state <- roll_event(old, as.integer(value))
      remember(m, old)
    } else if (command == "THROW") {
      old <- m$state
      dart_event(m, value)
      remember(m, old)
    } else if (command == "SUB") {
      player <- side(args[1L])
      outgoing <- as.integer(args[2L])
      incoming <- as.integer(args[3L])
      lineup <- m$state$lineups[[player]]
      position <- match(outgoing, lineup)
      if (is.na(position)) score_error("player not on court")
      if (incoming %in% lineup) score_error("player already on court")
      if (m$state$subs[player] >= 6L) score_error("no substitutions left")
      remember(m, c(2L, player, position, outgoing))
      m$state$lineups[[player]][position] <- incoming
      m$state$subs[player] <- m$state$subs[player] + 1L
    } else {
      player <- side(args[1L])
      if (m$state$timeouts[player] >= 2L) score_error("no timeouts left")
      remember(m, c(3L, player))
      m$state$timeouts[player] <- m$state$timeouts[player] + 1L
    }
  }
}
completed_text <- function(record, winner = 1L) {
  values <- record[1:2]
  if (winner == 2L) values <- rev(values)
  text <- pair_text(values)
  if (record[3L] == 2L) return(paste0("[", text, "]"))
  if (record[3L] == 1L) return(paste0(text, "(", record[4L], ")"))
  text
}
situation <- function(m, player) {
  outcome <- rally_outcome(m, player)
  if (outcome[3L]) return("match point")
  if (outcome[2L]) return(if (m$sport %in% c("TENNIS", "VOLLEYBALL")) "set point" else "game point")
  if (outcome[1L]) return(if (player == rally_server(m)) "game point" else "break point")
  ""
}
score_line <- function(m) {
  s <- m$state
  if (m$sport == "BOWLING") {
    parts <- paste0(m$id, ": ", m$names[1L])
    scores <- bowling_scores(s)
    cumulative <- 0L
    for (frame in 1:10) {
      if (!length(s$frames[[frame]])) break
      text <- paste(s$marks[[frame]], collapse = "")
      if (!is.na(scores[frame])) {
        cumulative <- cumulative + scores[frame]
        text <- paste0(text, "(", cumulative, ")")
      }
      parts <- c(parts, text)
    }
    return(paste(parts, collapse = " "))
  }
  names <- m$names
  if (s$winner == 0L) {
    player <- if (m$sport %in% rally_sports) rally_server(m) else s$server
    names[player] <- paste0(names[player], "*")
  }
  parts <- paste0(m$id, ": ", names[1L], " vs ", names[2L])
  if (m$sport == "DARTS") {
    parts <- c(parts, "sets", pair_text(s$won), "legs", pair_text(s$legs), "score", pair_text(s$remaining))
    if (s$winner == 0L) {
      if (length(s$turn)) parts <- c(parts, "turn", s$turn)
      answer <- checkout(s$remaining[s$server], 3L - length(s$turn))
      if (length(answer)) parts <- c(parts, "checkout", answer)
    }
  } else {
    parts <- c(parts, vapply(s$completed, completed_text, character(1L)))
    if (s$winner == 0L) {
      if (m$sport == "TENNIS") {
        mode <- tennis_mode(m)
        if (mode == "SUPER") {
          parts <- c(parts, paste0("[", pair_text(s$p), "]"))
        } else {
          parts <- c(parts, pair_text(s$g))
          if (mode == "TB") {
            parts <- c(parts, pair_text(s$p))
          } else if (m$options$DEUCE == "AD" && min(s$p) >= 3L) {
            if (s$p[1L] == s$p[2L]) {
              label <- "40-40"
            } else if (s$p[1L] > s$p[2L]) {
              label <- "AD-40"
            } else {
              label <- "40-AD"
            }
            parts <- c(parts, label)
          } else {
            labels <- c("0", "15", "30", "40")
            parts <- c(parts, pair_text(labels[s$p + 1L]))
          }
        }
      } else {
        parts <- c(parts, pair_text(s$p))
        if (m$sport == "VOLLEYBALL") parts <- c(parts, "server", s$lineups[[s$server]][1L])
      }
      for (player in 1:2) {
        label <- situation(m, player)
        if (label != "") parts <- c(parts, paste0("(", label, " ", m$names[player], ")"))
      }
    }
  }
  paste(parts, collapse = " ")
}
stats_lines <- function(m) {
  s <- m$state
  stats <- s$stats
  if (m$sport == "BOWLING") {
    marks <- unlist(s$marks, use.names = FALSE)
    open <- sum(vapply(s$frames, function(rolls) length(rolls) >= 2L && rolls[1L] != 10L && sum(rolls[1:2]) < 10L, logical(1L)))
    future <- s
    while (future$winner == 0L) future <- roll_event(future, future$standing)
    maximum <- sum(bowling_scores(future))
    return(paste0(m$id, " ", m$names[1L], ": strikes ", sum(marks == "X"), " spares ", sum(marks == "/"), " open ", open, " max ", maximum))
  }
  output <- character()
  for (player in 1:2) {
    if (m$sport == "DARTS") {
      darts <- stats$darts[player]
      average <- if (darts == 0L) 0L else (stats$scored[player] * 300L) %/% darts
      text <- paste0("darts ", darts, " average ", sprintf("%d.%02d", as.integer(average %/% 100L), as.integer(average %% 100L)),
                     " busts ", stats$busts[player], " high ", stats$high[player], " tons ", stats$tons[player],
                     " 180s ", stats$maximums[player], " doubles ", stats$hits[player], "/", stats$attempts[player])
    } else {
      text <- paste0("points ", stats$points[player], " serve ", stats$servewins[player], "/", stats$served[player], " run ", stats$runmax[player])
      if (m$sport == "TENNIS") {
        text <- paste0(text, " holds ", stats$holds[player], "/", stats$games[player], " breaks ", stats$breaks[player],
                       " break points ", stats$converted[player], "/", stats$opportunities[player])
      } else if (m$sport == "VOLLEYBALL") {
        text <- paste0(text, " subs ", s$subs[player], " timeouts ", s$timeouts[player], " lineup ", paste(s$lineups[[player]], collapse = ","))
      }
    }
    output <- c(output, paste0(m$id, " ", m$names[player], ": ", text))
  }
  output
}
result_line <- function(m) {
  s <- m$state
  if (s$winner == 0L) score_error("match not finished")
  if (m$sport == "BOWLING") return(paste0(m$id, ": ", m$names[1L], " ", sum(bowling_scores(s))))
  winner <- s$winner
  paste0(m$id, ": ", m$names[winner], " def. ", m$names[other(winner)], " ",
         paste(vapply(s$completed, completed_text, character(1L), winner = winner), collapse = " "))
}
execute <- function(line, matches) {
  tokens <- strsplit(line, " ", fixed = TRUE)[[1L]]
  command <- tokens[1L]
  if (command == "MATCH") {
    if (!is.null(matches[[tokens[2L]]])) score_error("duplicate match")
    m <- create_match(tokens)
    matches[[m$id]] <- m
    return(character())
  }
  if (command == "CHECKOUT") {
    answer <- checkout(as.integer(tokens[2L]))
    text <- if (!length(answer)) "none" else paste(answer, collapse = " ")
    return(paste0("checkout ", tokens[2L], ": ", text))
  }
  if (command == "STANDINGS") {
    totals <- new.env(hash = TRUE, parent = emptyenv())
    for (id in ls(matches, all.names = TRUE)) {
      m <- matches[[id]]
      if (m$sport != "BOWLING" && m$state$winner != 0L) {
        for (player in 1:2) {
          name <- m$names[player]
          value <- totals[[name]]
          if (is.null(value)) value <- c(0L, 0L)
          index <- if (player == m$state$winner) 1L else 2L
          value[index] <- value[index] + 1L
          totals[[name]] <- value
        }
      }
    }
    names <- ls(totals, all.names = TRUE)
    if (!length(names)) return("standings: none")
    wins <- vapply(names, function(name) totals[[name]][1L], integer(1L))
    losses <- vapply(names, function(name) totals[[name]][2L], integer(1L))
    names <- names[order(-wins, losses, names, method = "radix")]
    entries <- vapply(names, function(name) paste(name, pair_text(totals[[name]])), character(1L))
    return(paste0("standings: ", paste(entries, collapse = ", ")))
  }
  m <- matches[[tokens[2L]]]
  if (is.null(m)) score_error("unknown match")
  if (command %in% c("POINT", "ROLL", "THROW", "SUB", "TIMEOUT")) {
    event(m, command, tokens[seq.int(3L, length(tokens))])
  } else if (command == "UNDO") {
    undo_event(m)
  } else if (command == "SCORE") {
    return(score_line(m))
  } else if (command == "STATS") {
    return(stats_lines(m))
  } else if (command == "RESULT") {
    return(result_line(m))
  }
  character()
}
input <- file("stdin", open = "r")
count <- as.integer(readLines(input, n = 1L))
matches <- new.env(hash = TRUE, parent = emptyenv())
for (i in seq_len(count)) {
  line <- readLines(input, n = 1L)
  output <- tryCatch(execute(line, matches), error = function(error) paste("ERROR", conditionMessage(error)))
  if (length(output)) cat(paste(output, collapse = "\n"), "\n", sep = "")
}
close(input)
