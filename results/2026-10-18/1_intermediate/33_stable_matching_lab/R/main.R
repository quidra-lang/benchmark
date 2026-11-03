library(gmp)

fail <- function(message) {
  stop(structure(list(message = message, call = NULL),
                 class = c("command_error", "error", "condition")))
}
rank_in <- function(preference, partner) match(partner, preference, nomatch = length(preference) + 1L)
list_text <- function(values) if (length(values)) paste(values, collapse = " ") else "-"
receivers <- function(market) seq.int(market$proposers + 1L, length(market$names))
partner_name <- function(market, partner) if (partner == 0L) "*" else market$names[partner]
pair_text <- function(market, matching) {
  paste(vapply(seq_len(market$proposers), function(p) {
    paste0(market$names[p], "-", partner_name(market, matching[p]))
  }, character(1)), collapse = " ")
}
rotation_text <- function(market, matching, rotation) {
  paste(paste0(market$names[rotation], "-", market$names[matching[rotation]]), collapse = " ")
}
allocation_text <- function(market, allocation) {
  houses <- rep("*", length(allocation))
  assigned <- allocation > 0L
  houses[assigned] <- market$houses[allocation[assigned]]
  paste(paste0(market$names, "-", houses), collapse = " ")
}
require_kind <- function(market, kind) {
  if (market$kind != kind) fail(paste("WRONG TYPE", market$name))
}
agent_index <- function(market, name, side = NULL) {
  index <- match(name, market$names, nomatch = 0L)
  if (index == 0L) fail(paste("UNKNOWN AGENT", name))
  if (identical(side, "PROPOSER") && index > market$proposers) fail(paste("NOT PROPOSER", name))
  if (identical(side, "RECEIVER") && index <= market$proposers) fail(paste("NOT RECEIVER", name))
  index
}

deferred <- function(market, reverse = FALSE, verbose = FALSE) {
  n <- length(market$names)
  next_position <- rep.int(1L, n)
  counts <- integer(n)
  holding <- rep(list(integer()), n)
  preference_lengths <- lengths(market$preferences)
  able <- function(agent) counts[agent] < market$capacities[agent] && next_position[agent] <= preference_lengths[agent]
  side <- if (reverse) receivers(market) else seq_len(market$proposers)
  queue <- side[vapply(side, able, logical(1))]
  proposals <- 0L
  history <- character()
  while (length(queue)) {
    proposer <- queue[1L]
    queue <- queue[-1L]
    receiver <- market$preferences[[proposer]][next_position[proposer]]
    next_position[proposer] <- next_position[proposer] + 1L
    proposals <- proposals + 1L
    action <- "REJECT"
    preference <- market$preferences[[receiver]]
    if (proposer %in% preference) {
      if (length(holding[[receiver]]) < market$capacities[receiver]) {
        holding[[receiver]] <- c(holding[[receiver]], proposer)
        counts[proposer] <- counts[proposer] + 1L
        action <- "HOLD"
      } else {
        worst <- which.max(rank_in(preference, holding[[receiver]]))
        rejected <- holding[[receiver]][worst]
        if (rank_in(preference, proposer) < rank_in(preference, rejected)) {
          holding[[receiver]][worst] <- proposer
          counts[rejected] <- counts[rejected] - 1L
          counts[proposer] <- counts[proposer] + 1L
          action <- paste("HOLD REJECT", market$names[rejected])
          if (able(rejected) && !rejected %in% queue) queue <- c(queue, rejected)
        }
      }
    }
    if (verbose) history <- c(history, paste("PROPOSE", market$names[proposer], market$names[receiver], action))
    if (able(proposer)) queue <- c(queue, proposer)
  }
  matching <- integer(market$proposers)
  receiving <- if (reverse) seq_len(market$proposers) else receivers(market)
  for (receiver in receiving) {
    for (proposer in holding[[receiver]]) {
      if (reverse) matching[receiver] <- proposer else matching[proposer] <- receiver
    }
  }
  list(matching = matching, proposals = proposals, history = history)
}

boston <- function(market) {
  matching <- integer(market$proposers)
  remaining <- market$capacities
  rounds <- max(lengths(market$preferences[seq_len(market$proposers)]))
  applications <- 0L
  for (round in seq_len(rounds)) {
    applied <- integer(market$proposers)
    for (proposer in seq_len(market$proposers)) {
      if (matching[proposer] == 0L && length(market$preferences[[proposer]]) >= round) {
        applied[proposer] <- market$preferences[[proposer]][round]
        applications <- applications + 1L
      }
    }
    for (receiver in receivers(market)) {
      for (proposer in market$preferences[[receiver]]) {
        if (remaining[receiver] > 0L && applied[proposer] == receiver) {
          matching[proposer] <- receiver
          remaining[receiver] <- remaining[receiver] - 1L
        }
      }
    }
  }
  list(matching = matching, proposals = applications, history = character())
}

exposed_rotations <- function(market, matching) {
  owner <- integer(length(market$names))
  successor <- integer(market$proposers)
  matched <- which(matching > 0L)
  owner[matching[matched]] <- matched
  for (proposer in matched) {
    preference <- market$preferences[[proposer]]
    later <- tail(preference, -rank_in(preference, matching[proposer]))
    for (receiver in later) {
      ranking <- market$preferences[[receiver]]
      if (proposer %in% ranking && (owner[receiver] == 0L || rank_in(ranking, proposer) < rank_in(ranking, owner[receiver]))) {
        successor[proposer] <- owner[receiver]
        break
      }
    }
  }
  covered <- rep(FALSE, market$proposers)
  rotations <- list()
  for (start in seq_len(market$proposers)) {
    if (covered[start]) next
    path <- integer()
    point <- start
    while (point > 0L && !point %in% path) {
      path <- c(path, point)
      point <- successor[point]
    }
    if (point == start) {
      rotations[[length(rotations) + 1L]] <- path
      covered[path] <- TRUE
    }
  }
  rotations
}

matching_metrics <- function(market, matching) {
  ranks <- integer()
  for (proposer in which(matching > 0L)) {
    receiver <- matching[proposer]
    ranks <- c(ranks, rank_in(market$preferences[[proposer]], receiver), rank_in(market$preferences[[receiver]], proposer))
  }
  c(cost = sum(ranks), regret = max(0L, ranks))
}

enumerate_matchings <- function(market) {
  if (any(market$capacities[receivers(market)] != 1L)) fail("NOT ONE TO ONE")
  matchings <- list(deferred(market)$matching)
  origins <- vias <- 0L
  rotations <- character()
  index <- 1L
  while (index <= length(matchings)) {
    matching <- matchings[[index]]
    for (rotation in exposed_rotations(market, matching)) {
      notation <- rotation_text(market, matching, rotation)
      identifier <- match(notation, rotations, nomatch = 0L)
      if (identifier == 0L) {
        rotations <- c(rotations, notation)
        identifier <- length(rotations)
      }
      following <- matching
      following[rotation] <- matching[c(rotation[-1L], rotation[1L])]
      if (!any(vapply(matchings, identical, logical(1), following))) {
        if (length(matchings) == 50L) fail("TOO MANY MATCHINGS")
        matchings[[length(matchings) + 1L]] <- following
        origins <- c(origins, index)
        vias <- c(vias, identifier)
      }
    }
    index <- index + 1L
  }
  list(matchings = matchings, origins = origins, vias = vias, rotations = rotations)
}

check_pairs <- function(market, words) {
  if (market$kind == "HOUSES") fail(paste("WRONG TYPE", market$name))
  matching <- integer(length(market$names))
  counts <- integer(length(market$names))
  two <- market$kind == "MARKET"
  for (word in tail(words, -2L)) {
    pair <- strsplit(word, "-", fixed = TRUE)[[1L]]
    first <- agent_index(market, pair[1L], if (two) "PROPOSER" else NULL)
    second <- agent_index(market, pair[2L], if (two) "RECEIVER" else NULL)
    if (matching[first] > 0L) fail(paste("DUPLICATE AGENT", pair[1L]))
    if (two) {
      counts[second] <- counts[second] + 1L
      if (counts[second] > market$capacities[second]) fail(paste("OVER CAPACITY", pair[2L]))
    } else {
      if (first == second || matching[second] > 0L) fail(paste("DUPLICATE AGENT", pair[2L]))
      matching[second] <- first
    }
    matching[first] <- second
  }
  unacceptable <- blocking <- character()
  if (two) {
    for (proposer in seq_len(market$proposers)) {
      receiver <- matching[proposer]
      if (receiver > 0L && (!receiver %in% market$preferences[[proposer]] || !proposer %in% market$preferences[[receiver]])) {
        unacceptable <- c(unacceptable, paste("UNACCEPTABLE", market$names[proposer], market$names[receiver]))
      }
      for (other in receivers(market)) {
        if (other == receiver || !other %in% market$preferences[[proposer]] || !proposer %in% market$preferences[[other]]) next
        if (rank_in(market$preferences[[proposer]], other) >= rank_in(market$preferences[[proposer]], receiver)) next
        partners <- which(matching[seq_len(market$proposers)] == other)
        worst <- max(0L, rank_in(market$preferences[[other]], partners))
        if (length(partners) < market$capacities[other] || rank_in(market$preferences[[other]], proposer) < worst) {
          blocking <- c(blocking, paste("BLOCKING", market$names[proposer], market$names[other]))
        }
      }
    }
  } else {
    for (first in seq_along(market$names)) {
      for (second in which(seq_along(market$names) > first)) {
        mutual <- second %in% market$preferences[[first]] && first %in% market$preferences[[second]]
        if (matching[first] == second) {
          if (!mutual) unacceptable <- c(unacceptable, paste("UNACCEPTABLE", market$names[first], market$names[second]))
        } else if (mutual && rank_in(market$preferences[[first]], second) < rank_in(market$preferences[[first]], matching[first]) &&
                   rank_in(market$preferences[[second]], first) < rank_in(market$preferences[[second]], matching[second])) {
          blocking <- c(blocking, paste("BLOCKING", market$names[first], market$names[second]))
        }
      }
    }
  }
  if (!length(unacceptable) && !length(blocking)) return(paste("CHECK", market$name, "STABLE"))
  c(sprintf("CHECK %s UNSTABLE unacceptable=%d blocking=%d", market$name, length(unacceptable), length(blocking)), unacceptable, blocking)
}

remove_pair <- function(lists, first, second) {
  lists[[first]] <- lists[[first]][lists[[first]] != second]
  lists[[second]] <- lists[[second]][lists[[second]] != first]
  lists
}
table_lines <- function(market, lists) {
  vapply(seq_along(market$names), function(agent) {
    paste("TABLE", market$names[agent], list_text(market$names[lists[[agent]]]))
  }, character(1))
}
first_empty <- function(lists) match(0L, lengths(lists), nomatch = 0L)

roommates <- function(market, verbose) {
  require_kind(market, "ROOMS")
  incomplete <- which(lengths(market$preferences) < length(market$names) - 1L)
  if (length(incomplete)) fail(paste("INCOMPLETE", market$names[incomplete[1L]]))
  lists <- market$preferences
  held <- integer(length(market$names))
  queue <- seq_along(market$names)
  proposals <- 0L
  failure <- 0L
  while (length(queue)) {
    proposer <- queue[1L]
    queue <- queue[-1L]
    receiver <- lists[[proposer]][1L]
    if (held[receiver] > 0L) queue <- c(queue, held[receiver])
    held[receiver] <- proposer
    proposals <- proposals + 1L
    removed <- tail(lists[[receiver]], -match(proposer, lists[[receiver]]))
    for (other in removed) lists <- remove_pair(lists, receiver, other)
    failure <- first_empty(lists)
    if (failure > 0L) break
  }
  history <- if (failure == 0L && verbose) table_lines(market, lists) else character()
  rotations <- 0L
  while (failure == 0L) {
    multiple <- which(lengths(lists) >= 2L)
    if (!length(multiple)) break
    point <- multiple[1L]
    path <- integer()
    while (!point %in% path) {
      path <- c(path, point)
      second <- lists[[point]][2L]
      point <- tail(lists[[second]], 1L)
    }
    rotation <- path[seq.int(match(point, path), length(path))]
    front <- vapply(rotation, function(agent) lists[[agent]][1L], integer(1))
    rotations <- rotations + 1L
    notation <- paste(paste0(market$names[rotation], "-", market$names[front]), collapse = " ")
    history <- c(history, paste("ROTATION", rotations, notation))
    removals <- list()
    for (index in seq_along(rotation)) {
      receiver <- front[index %% length(front) + 1L]
      for (other in tail(lists[[receiver]], -match(rotation[index], lists[[receiver]]))) {
        removals[[length(removals) + 1L]] <- c(receiver, other)
      }
    }
    for (pair in removals) lists <- remove_pair(lists, pair[1L], pair[2L])
    if (verbose) history <- c(history, table_lines(market, lists))
    failure <- first_empty(lists)
  }
  rows <- c(sprintf("ROOMMATES %s proposals=%d", market$name, proposals), history)
  if (failure > 0L) return(c(rows, paste("NO STABLE MATCHING", market$names[failure])))
  partners <- vapply(lists, `[`, integer(1), 1L)
  first <- which(seq_along(partners) < partners)
  c(rows, paste("MATCHING", paste(paste0(market$names[first], "-", market$names[partners[first]]), collapse = " ")))
}

effective_list <- function(market, agent) {
  preference <- market$preferences[[agent]]
  position <- match(agent, preference, nomatch = 0L)
  if (position) head(preference, position) else c(preference, agent)
}

ttc <- function(market) {
  remaining <- rep(TRUE, length(market$names))
  allocation <- integer(length(market$names))
  effective <- lapply(seq_along(market$names), function(agent) effective_list(market, agent))
  cycles <- character()
  while (any(remaining)) {
    pointing <- integer(length(market$names))
    for (agent in which(remaining)) pointing[agent] <- effective[[agent]][remaining[effective[[agent]]]][1L]
    point <- which(remaining)[1L]
    path <- integer()
    while (!point %in% path) {
      path <- c(path, point)
      point <- pointing[point]
    }
    cycle <- path[seq.int(match(point, path), length(path))]
    allocation[cycle] <- pointing[cycle]
    remaining[cycle] <- FALSE
    notation <- paste(paste0(market$names[cycle], ":", market$houses[pointing[cycle]]), collapse = " ")
    cycles <- c(cycles, paste("CYCLE", length(cycles) + 1L, notation))
  }
  c(sprintf("TTC %s cycles=%d", market$name, length(cycles)), cycles, paste("ALLOCATION", allocation_text(market, allocation)))
}

serial <- function(market, words) {
  order <- integer()
  for (word in tail(words, -2L)) {
    agent <- agent_index(market, word)
    if (agent %in% order) fail(paste("DUPLICATE AGENT", word))
    order <- c(order, agent)
  }
  if (length(order) != length(market$names)) fail("BAD ORDER")
  remaining <- rep(TRUE, length(market$names))
  allocation <- integer(length(market$names))
  for (agent in order) {
    preference <- market$preferences[[agent]]
    available <- preference[remaining[preference]]
    if (length(available)) {
      allocation[agent] <- available[1L]
      remaining[available[1L]] <- FALSE
    }
  }
  worse <- which(vapply(seq_along(market$names), function(agent) {
    !allocation[agent] %in% effective_list(market, agent)
  }, logical(1)))
  c(sprintf("SERIAL %s assigned=%d", market$name, sum(allocation > 0L)),
    paste("ALLOCATION", allocation_text(market, allocation)), paste("WORSE", list_text(market$names[worse])))
}

hospital_report <- function(market) {
  resident <- deferred(market)$matching
  hospital <- deferred(market, TRUE)$matching
  rows <- c(sprintf("HR %s residents=%d hospitals=%d", market$name, market$proposers, length(market$names) - market$proposers),
            paste("RESIDENT-OPTIMAL", pair_text(market, resident)), paste("HOSPITAL-OPTIMAL", pair_text(market, hospital)),
            paste("UNMATCHED", list_text(market$names[which(resident == 0L)])))
  rural <- identical(resident > 0L, hospital > 0L)
  for (receiver in receivers(market)) {
    first <- which(resident == receiver)
    second <- which(hospital == receiver)
    same <- identical(first, second)
    capacity <- market$capacities[receiver]
    rows <- c(rows, sprintf("HOSPITAL %s cap=%d resident=%d hospital=%d same=%s", market$names[receiver], capacity,
                            length(first), length(second), if (same) "YES" else "NO"))
    rural <- rural && length(first) == length(second) && (length(first) == capacity || same)
  }
  c(rows, if (rural) "RURAL HOLDS" else "RURAL FAILS")
}

manipulate <- function(market, proposer) {
  truth <- market$preferences[[proposer]]
  baseline_b <- boston(market)$matching[proposer]
  baseline_g <- deferred(market)$matching[proposer]
  swaps <- max(0L, length(truth) - 1L)
  rows <- sprintf("MANIPULATE %s %s boston=%s gs=%s swaps=%d", market$name, market$names[proposer],
                  partner_name(market, baseline_b), partner_name(market, baseline_g), swaps)
  for (index in seq_len(swaps)) {
    trial <- market
    trial$preferences[[proposer]][c(index, index + 1L)] <- truth[c(index + 1L, index)]
    results <- c(boston(trial)$matching[proposer], deferred(trial)$matching[proposer])
    baselines <- c(baseline_b, baseline_g)
    for (kind in seq_len(2L)) {
      if (rank_in(truth, results[kind]) < rank_in(truth, baselines[kind])) {
        rows <- c(rows, sprintf("IMPROVE %s %d %s %s result=%s", c("BOSTON", "GS")[kind], index,
                                market$names[truth[index]], market$names[truth[index + 1L]], partner_name(market, results[kind])))
      }
    }
  }
  if (length(rows) == 1L) rows <- c(rows, "NO IMPROVEMENT")
  rows
}

gcd <- function(first, second) {
  while (second != 0L) {
    remainder <- first %% second
    first <- second
    second <- remainder
  }
  first
}
statistics <- function(market) {
  saved <- market$current
  if (is.null(saved)) fail("NO MATCHING")
  matched <- which(saved$matching > 0L)
  pairs <- length(matched)
  proposer_ranks <- vapply(matched, function(p) rank_in(market$preferences[[p]], saved$matching[p]), integer(1))
  receiver_ranks <- vapply(matched, function(p) rank_in(market$preferences[[saved$matching[p]]], p), integer(1))
  ranks <- list(proposer_ranks, receiver_ranks)
  unmatched <- c(market$proposers - pairs, length(market$names) - market$proposers - length(unique(saved$matching[matched])))
  rows <- sprintf("STATS %s source=%s pairs=%d", market$name, saved$source, pairs)
  for (side in seq_len(2L)) {
    total <- sum(ranks[[side]])
    average <- truncated <- "-"
    if (pairs > 0L) {
      divisor <- gcd(total, pairs)
      average <- sprintf("%d/%d", total %/% divisor, pairs %/% divisor)
      cents <- (100L * total) %/% pairs
      truncated <- sprintf("%d.%02d", cents %/% 100L, cents %% 100L)
    }
    rows <- c(rows, sprintf("%s sum=%d average=%s truncated=%s first=%d unmatched=%d", c("PROPOSERS", "RECEIVERS")[side],
                            total, average, truncated, sum(ranks[[side]] == 1L), unmatched[side]))
  }
  rows
}

show_market <- function(market) {
  if (market$kind == "MARKET") {
    rows <- sprintf("SHOW %s MARKET proposers=%d receivers=%d", market$name, market$proposers, length(market$names) - market$proposers)
  } else rows <- sprintf("SHOW %s %s agents=%d", market$name, market$kind, length(market$names))
  for (agent in seq_along(market$names)) {
    if (market$kind == "MARKET") {
      prefix <- if (agent <= market$proposers) paste("PROPOSER", market$names[agent]) else {
        sprintf("RECEIVER %s cap=%d", market$names[agent], market$capacities[agent])
      }
    } else {
      prefix <- paste("AGENT", market$names[agent])
      if (market$kind == "HOUSES") prefix <- paste0(prefix, " house=", market$houses[agent])
    }
    names <- if (market$kind == "HOUSES") market$houses else market$names
    rows <- c(rows, paste(prefix, list_text(names[market$preferences[[agent]]])))
  }
  if (market$kind == "MARKET") rows <- c(rows, paste("CURRENT", if (is.null(market$current)) "-" else market$current$source))
  rows
}

new_market <- function(words) {
  command <- words[1L]
  kind <- if (command == "RANDOM") "MARKET" else command
  names <- houses <- character()
  proposers <- 0L
  if (command == "RANDOM") {
    proposers <- as.integer(words[3L])
    names <- c(paste0("P", seq_len(proposers)), paste0("R", seq_len(proposers)))
  } else {
    for (word in tail(words, -2L)) {
      if (word == "|") {
        proposers <- length(names)
        next
      }
      pair <- strsplit(word, ":", fixed = TRUE)[[1L]]
      if (pair[1L] %in% names) fail(paste("DUPLICATE AGENT", pair[1L]))
      if (kind == "HOUSES") {
        if (pair[2L] %in% houses) fail(paste("DUPLICATE HOUSE", pair[2L]))
        houses <- c(houses, pair[2L])
      }
      names <- c(names, pair[1L])
    }
  }
  market <- list(name = words[2L], kind = kind, names = names, houses = houses, proposers = proposers,
                 preferences = rep(list(integer()), length(names)), capacities = rep.int(1L, length(names)), current = NULL)
  if (command == "RANDOM") {
    state <- as.bigz(words[4L])
    for (agent in seq_along(names)) {
      preference <- if (agent <= proposers) receivers(market) else seq_len(proposers)
      for (size in rev(seq_len(proposers)[-1L])) {
        state <- (48271L * state) %% 2147483647L
        index <- as.integer(state %% size) + 1L
        preference[c(size, index)] <- preference[c(index, size)]
      }
      market$preferences[[agent]] <- preference
    }
  }
  market
}

execute <- function(markets, line) {
  words <- strsplit(line, " ", fixed = TRUE)[[1L]]
  command <- words[1L]
  name <- words[2L]
  if (command %in% c("MARKET", "ROOMS", "HOUSES", "RANDOM")) {
    if (exists(name, markets, inherits = FALSE)) fail(paste("DUPLICATE MARKET", name))
    market <- new_market(words)
    rows <- if (command == "RANDOM") sprintf("RANDOM %s n=%d seed=%s", name, market$proposers, words[4L]) else {
      if (market$kind == "MARKET") sprintf("MARKET %s proposers=%d receivers=%d", name, market$proposers, length(market$names) - market$proposers) else {
        sprintf("%s %s agents=%d", command, name, length(market$names))
      }
    }
    assign(name, market, markets)
    return(rows)
  }
  if (!exists(name, markets, inherits = FALSE)) fail(paste("UNKNOWN MARKET", name))
  market <- get(name, markets, inherits = FALSE)
  if (command == "SHOW") return(show_market(market))
  if (command == "PREF") {
    agent <- agent_index(market, words[3L])
    names <- if (market$kind == "HOUSES") market$houses else market$names
    preference <- integer()
    for (word in tail(words, -3L)) {
      choice <- match(word, names, nomatch = 0L)
      if (choice == 0L || (market$kind == "ROOMS" && choice == agent) ||
          (market$kind == "MARKET" && (agent <= market$proposers) == (choice <= market$proposers))) fail(paste("BAD CHOICE", word))
      if (choice %in% preference) fail(paste("DUPLICATE CHOICE", word))
      preference <- c(preference, choice)
    }
    market$preferences[[agent]] <- preference
    if (market$kind == "MARKET") market$current <- NULL
    rows <- sprintf("PREF %s %s length=%d", name, words[3L], length(preference))
  } else if (command == "CHECK") {
    return(check_pairs(market, words))
  } else if (command == "ROOMMATES") {
    return(roommates(market, length(words) == 3L))
  } else if (command %in% c("TTC", "SERIAL")) {
    require_kind(market, "HOUSES")
    return(if (command == "TTC") ttc(market) else serial(market, words))
  } else {
    require_kind(market, "MARKET")
    if (command == "CAPACITY") {
      receiver <- agent_index(market, words[3L], "RECEIVER")
      capacity <- as.integer(words[4L])
      market$capacities[receiver] <- capacity
      market$current <- NULL
      rows <- sprintf("CAPACITY %s %s %d", name, words[3L], capacity)
    } else if (command %in% c("GS", "GSR", "BOSTON")) {
      run <- if (command == "BOSTON") boston(market) else deferred(market, command == "GSR", length(words) == 3L)
      market$current <- list(source = command, matching = run$matching)
      rows <- c(sprintf("%s %s %s=%d", command, name, if (command == "BOSTON") "applications" else "proposals", run$proposals),
                run$history, paste("MATCHING", pair_text(market, run$matching)))
    } else if (command == "HR") {
      return(hospital_report(market))
    } else if (command == "MANIPULATE") {
      return(manipulate(market, agent_index(market, words[3L], "PROPOSER")))
    } else if (command == "STATS") {
      return(statistics(market))
    } else {
      lattice <- enumerate_matchings(market)
      if (command == "LATTICE") {
        rows <- sprintf("LATTICE %s matchings=%d rotations=%d", name, length(lattice$matchings), length(lattice$rotations))
        for (index in seq_along(lattice$matchings)) {
          matching <- lattice$matchings[[index]]
          metrics <- matching_metrics(market, matching)
          origin <- if (index == 1L) "-" else as.character(lattice$origins[index])
          via <- if (index == 1L) "-" else as.character(lattice$vias[index])
          rows <- c(rows, sprintf("MATCHING %d from=%s via=%s cost=%d regret=%d %s", index, origin, via,
                                  metrics["cost"], metrics["regret"], pair_text(market, matching)))
        }
        for (index in seq_along(lattice$rotations)) rows <- c(rows, paste("ROTATION", index, lattice$rotations[index]))
        return(rows)
      }
      criterion <- if (command == "EGALITARIAN") "cost" else "regret"
      values <- vapply(lattice$matchings, function(matching) matching_metrics(market, matching)[criterion], integer(1))
      best <- which.min(values)
      market$current <- list(source = command, matching = lattice$matchings[[best]])
      rows <- c(sprintf("%s %s matching=%d %s=%d", command, name, best, criterion, values[best]),
                paste("MATCHING", pair_text(market, market$current$matching)))
    }
  }
  assign(name, market, markets)
  rows
}

main <- function() {
  input <- readLines(file("stdin"), warn = FALSE)
  markets <- new.env(parent = emptyenv())
  for (index in seq_len(as.integer(input[1L]))) {
    rows <- tryCatch(execute(markets, input[index + 1L]), command_error = function(problem) paste("ERROR", conditionMessage(problem)))
    cat(paste(rows, collapse = "\n"), "\n", sep = "")
  }
}
main()
