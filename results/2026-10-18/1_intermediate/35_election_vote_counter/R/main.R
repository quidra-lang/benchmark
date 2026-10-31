library(gmp)

summary_methods <- c("PLURALITY", "RUNOFF", "IRV", "COOMBS", "BUCKLIN", "BORDA",
                     "BALDWIN", "NANSON", "BLACK", "VETO", "COPELAND",
                     "MINIMAX WINNING", "SCHULZE", "RANKEDPAIRS", "KEMENY")
fail <- function(message) {
  stop(structure(list(message = message, call = NULL),
                 class = c("command_error", "error", "condition")))
}
name_list <- function(election, candidates, separator = ", ") {
  paste(election$names[candidates], collapse = separator)
}
tie_text <- function(tie) if (tie) " (tie)" else ""
money <- function(value) sprintf("%d.%02d", value %/% 100L, value %% 100L)
value_list <- function(election, field, scores, cents = FALSE) {
  values <- if (cents) money(scores[field]) else as.character(scores[field])
  paste(paste(election$names[field], values), collapse = ", ")
}
field_id <- function(field) sum(bitwShiftL(1L, field - 1L))
members <- function(field, count) which(bitwAnd(field, bitwShiftL(1L, seq_len(count) - 1L)) != 0L)
effective <- function(ranking, field) ranking[ranking %in% field]
ordered <- function(election, field, scores, descending = TRUE) {
  field[order(if (descending) -scores[field] else scores[field], election$priority[field], method = "radix")]
}
finish <- function(election, order, tie, rows) {
  list(order = order, rows = c(rows, paste0("winner: ", election$names[order[1L]], tie_text(tie))))
}
candidate_index <- function(election, name) {
  index <- match(name, election$names, nomatch = 0L)
  if (index == 0L) fail(paste("unknown candidate", name))
  index
}
checked_names <- function(election, names) {
  result <- integer()
  for (name in names) {
    candidate <- candidate_index(election, name)
    if (candidate %in% result) fail(paste("duplicate candidate", name))
    result <- c(result, candidate)
  }
  result
}
new_election <- function(number, names) {
  tiebreak <- order(names, method = "radix")
  list(number = number, names = names, active = rep(TRUE, length(names)),
       tiebreak = tiebreak, priority = match(seq_along(names), tiebreak),
       votes = integer(), rankings = list(), ends = integer(), total = 0L,
       cache = new.env(parent = emptyenv()))
}

tallies <- function(election, field) {
  key <- as.character(field_id(field))
  if (exists(key, election$cache, inherits = FALSE)) return(get(key, election$cache, inherits = FALSE))
  count <- length(election$names)
  size <- length(field)
  first <- last <- borda <- integer(count)
  approval <- matrix(0L, size, count)
  nonblank <- 0L
  for (index in seq_along(election$votes)) {
    votes <- election$votes[index]
    ranking <- effective(election$rankings[[index]], field)
    positions <- match(seq_len(count), ranking, nomatch = count + 1L)
    if (length(ranking)) nonblank <- nonblank + votes
    first <- first + votes * (positions == 1L)
    if (length(ranking) == size) {
      last <- last + votes * (positions == size)
    } else {
      last <- last + votes * ((seq_len(count) %in% field) & positions == count + 1L)
    }
    borda <- borda + votes * pmax.int(0L, size - positions)
    approval <- approval + votes * outer(seq_len(size), positions, ">=")
  }
  result <- list(first = first, last = last, borda = borda, approval = approval, nonblank = nonblank)
  assign(key, result, election$cache)
  result
}
pairwise <- function(election) {
  if (exists("pairs", election$cache, inherits = FALSE)) return(election$cache$pairs)
  count <- length(election$names)
  result <- matrix(0L, count, count)
  for (index in seq_along(election$votes)) {
    ranking <- election$rankings[[index]]
    positions <- match(seq_len(count), ranking, nomatch = count + 1L)
    result <- result + election$votes[index] * outer(positions, positions, "<")
  }
  election$cache$pairs <- result
  result
}
majority <- function(field, scores) any(2L * scores[field] > sum(scores[field]))
look_back <- function(election, field, history) {
  choices <- field
  tie <- FALSE
  for (round in rev(seq_along(history))) {
    scores <- history[[round]]
    choices <- choices[scores[choices] == min(scores[choices])]
    if (round == length(history)) tie <- length(choices) > 1L
  }
  list(candidate = choices[which.max(election$priority[choices])], tie = tie)
}
condorcet <- function(election, field, loser = FALSE) {
  matrix <- pairwise(election)
  for (candidate in field) {
    others <- setdiff(field, candidate)
    all <- if (loser) all(matrix[candidate, others] < matrix[others, candidate]) else
      all(matrix[candidate, others] > matrix[others, candidate])
    if (all) return(candidate)
  }
  0L
}
elimination <- function(election, field, coombs = FALSE, exhausted = FALSE) {
  remaining <- field
  removed <- integer()
  history <- list()
  rows <- character()
  repeat {
    scores <- tallies(election, remaining)
    round <- length(rows) + 1L
    if (exhausted) {
      active <- sum(scores$first[remaining])
      row <- sprintf("round %d: active %d, exhausted %d", round, active, election$total - active)
    } else {
      row <- sprintf("round %d: %s", round, value_list(election, remaining, scores$first))
    }
    if (length(remaining) == 1L || majority(remaining, scores$first)) {
      order <- c(ordered(election, remaining, scores$first), rev(removed))
      rows <- c(rows, row)
      if (exhausted) return(list(order = order, rows = rows))
      return(finish(election, order, FALSE, rows))
    }
    if (coombs) {
      choices <- remaining[scores$last[remaining] == max(scores$last[remaining])]
      order <- ordered(election, choices, scores$first)
      choice <- list(candidate = tail(order, 1L), tie = length(choices) > 1L)
      row <- paste0(row, "; last ", value_list(election, remaining, scores$last))
    } else {
      history <- c(history, list(scores$first))
      choice <- look_back(election, remaining, history)
    }
    if (!exhausted) row <- paste0(row, "; eliminated ", election$names[choice$candidate], tie_text(choice$tie))
    rows <- c(rows, row)
    removed <- c(removed, choice$candidate)
    remaining <- setdiff(remaining, choice$candidate)
  }
}
runoff <- function(election, field) {
  first <- tallies(election, field)$first
  order <- ordered(election, field, first)
  rows <- paste0("round 1: ", value_list(election, field, first))
  tie <- FALSE
  if (!majority(field, first)) {
    finalists <- sort(order[1:2])
    advance <- length(order) >= 3L && first[order[2L]] == first[order[3L]]
    second <- tallies(election, finalists)$first
    tie <- second[order[1L]] == second[order[2L]]
    if (second[order[2L]] > second[order[1L]]) order[1:2] <- order[2:1]
    rows <- c(rows, paste0("finalists: ", name_list(election, finalists), tie_text(advance)),
              paste0("round 2: ", value_list(election, finalists, second)))
  }
  finish(election, order, tie, rows)
}
bucklin <- function(election, field) {
  scores <- tallies(election, field)
  line <- scores$nonblank %/% 2L + 1L
  rows <- paste("majority:", line)
  order <- effective(election$tiebreak, field)
  for (depth in seq_along(field)) {
    final <- scores$approval[depth, ]
    order <- order[order(-final[order], method = "radix")]
    rows <- c(rows, sprintf("round %d: %s", depth, value_list(election, field, final)))
    if (any(final[field] >= line)) break
  }
  finish(election, order, final[order[1L]] == final[order[2L]], rows)
}
borda_elimination <- function(election, field, nanson = FALSE) {
  remaining <- field
  tail <- integer()
  history <- list()
  rows <- character()
  while (length(remaining) >= 2L) {
    scores <- tallies(election, remaining)$borda
    row <- sprintf("round %d: %s", length(rows) + 1L, value_list(election, remaining, scores))
    if (nanson) {
      below <- remaining[scores[remaining] * length(remaining) < sum(scores[remaining])]
      if (!length(below)) {
        rows <- c(rows, row)
        break
      }
      row <- paste0(row, "; eliminated ", name_list(election, below))
      removed <- ordered(election, below, scores)
    } else {
      history <- c(history, list(scores))
      choice <- look_back(election, remaining, history)
      removed <- choice$candidate
      row <- paste0(row, "; eliminated ", election$names[choice$candidate], tie_text(choice$tie))
    }
    rows <- c(rows, row)
    remaining <- setdiff(remaining, removed)
    tail <- c(removed, tail)
  }
  order <- c(effective(election$tiebreak, remaining), tail)
  finish(election, order, nanson && length(remaining) > 1L, rows)
}
pair_lines <- function(election, field, matrix) {
  rows <- character()
  for (index in seq_along(field)) {
    first <- field[index]
    for (second in field[seq_along(field) > index]) {
      forward <- matrix[first, second]
      backward <- matrix[second, first]
      result <- if (forward == backward) "tie" else election$names[if (forward > backward) first else second]
      rows <- c(rows, sprintf("%s vs %s: %d-%d (%s)", election$names[first], election$names[second], forward, backward, result))
    }
  }
  rows
}
closure <- function(field, relation) {
  for (via in field) relation <- relation | outer(relation[, via], relation[via, ], "&")
  relation
}
condorcet_report <- function(election, field) {
  matrix <- pairwise(election)
  winner <- condorcet(election, field)
  loser <- condorcet(election, field, TRUE)
  weak <- closure(field, matrix >= t(matrix))
  strong <- closure(field, matrix > t(matrix))
  smith <- field[vapply(field, function(a) all(weak[a, field]), logical(1))]
  schwartz <- field[vapply(field, function(a) all(!strong[field, a] | strong[a, field]), logical(1))]
  list(order = integer(), rows = c(
    paste("winner:", if (winner == 0L) "NONE" else election$names[winner]),
    paste("loser:", if (loser == 0L) "NONE" else election$names[loser]),
    paste0("smith: ", name_list(election, smith)),
    paste0("schwartz: ", name_list(election, schwartz))))
}
topological <- function(election, field, relation) {
  remaining <- field
  order <- integer()
  tie <- FALSE
  while (length(remaining)) {
    choices <- remaining[vapply(remaining, function(a) !any(relation[setdiff(remaining, a), a]), logical(1))]
    if (!length(order)) tie <- length(choices) > 1L
    chosen <- choices[which.min(election$priority[choices])]
    order <- c(order, chosen)
    remaining <- setdiff(remaining, chosen)
  }
  list(order = order, tie = tie)
}
schulze <- function(election, field) {
  matrix <- pairwise(election)
  paths <- matrix * (matrix > t(matrix))
  for (via in field) {
    for (first in setdiff(field, via)) {
      for (second in setdiff(field, c(via, first))) {
        paths[first, second] <- max(paths[first, second], min(paths[first, via], paths[via, second]))
      }
    }
  }
  result <- topological(election, field, paths > t(paths))
  rows <- c(pair_lines(election, field, paths), paste0("ranking: ", name_list(election, result$order, " > ")))
  finish(election, result$order, result$tie, rows)
}
ranked_pairs <- function(election, field) {
  matrix <- pairwise(election)
  pairs <- matrix(integer(), nrow = 0L, ncol = 2L)
  for (first in field) {
    for (second in field) if (matrix[first, second] > matrix[second, first]) pairs <- rbind(pairs, c(first, second))
  }
  if (nrow(pairs)) {
    reverse <- pairs[, 2:1, drop = FALSE]
    order <- order(-matrix[pairs], matrix[reverse], election$priority[pairs[, 1L]],
                   election$priority[pairs[, 2L]], method = "radix")
    pairs <- pairs[order, , drop = FALSE]
  }
  locked <- reached <- matrix(FALSE, length(election$names), length(election$names))
  rows <- character()
  for (index in seq_len(nrow(pairs))) {
    first <- pairs[index, 1L]
    second <- pairs[index, 2L]
    accepted <- !reached[second, first]
    label <- if (accepted) "lock" else "skip"
    rows <- c(rows, sprintf("%s %s>%s %d-%d", label, election$names[first], election$names[second],
                            matrix[first, second], matrix[second, first]))
    if (accepted) {
      locked[first, second] <- reached[first, second] <- TRUE
      reached <- closure(field, reached)
    }
  }
  result <- topological(election, field, locked)
  finish(election, result$order, result$tie, rows)
}
kemeny <- function(election, field) {
  matrix <- pairwise(election)
  limit <- bitwShiftL(1L, length(election$names))
  best <- ways <- integer(limit)
  heads <- rep(list(integer()), limit)
  ways[1L] <- 1L
  for (subset in seq_len(limit - 1L)) {
    candidates <- members(subset, length(election$names))
    if (!all(candidates %in% field)) next
    index <- subset + 1L
    best[index] <- -1L
    for (candidate in candidates) {
      rest <- subset - bitwShiftL(1L, candidate - 1L)
      score <- best[rest + 1L] + sum(matrix[candidate, setdiff(candidates, candidate)])
      if (score > best[index]) {
        best[index] <- score
        ways[index] <- 0L
        heads[[index]] <- integer()
      }
      if (score == best[index]) {
        ways[index] <- ways[index] + ways[rest + 1L]
        heads[[index]] <- c(heads[[index]], candidate)
      }
    }
  }
  key <- field_id(field)
  remaining <- key
  order <- integer()
  while (remaining > 0L) {
    chosen <- effective(election$tiebreak, heads[[remaining + 1L]])[1L]
    order <- c(order, chosen)
    remaining <- remaining - bitwShiftL(1L, chosen - 1L)
  }
  rows <- c(paste("score:", best[key + 1L]), paste("optimal:", ways[key + 1L]),
            paste0("ranking: ", name_list(election, order, " > ")))
  finish(election, order, length(heads[[key + 1L]]) > 1L, rows)
}
stv <- function(election, field, seats) {
  values <- vapply(election$rankings, function(ranking) if (any(ranking %in% field)) 100L else 0L, integer(1))
  quota <- (100L * tallies(election, field)$nonblank) %/% (seats + 1L) + 1L
  continuing <- field
  elected <- integer()
  history <- list()
  rows <- paste0("quota: ", money(quota))
  repeat {
    scores <- integer(length(election$names))
    owners <- integer(length(election$votes))
    exhausted <- 0L
    for (index in seq_along(election$votes)) {
      if (values[index] == 0L) next
      ranking <- effective(election$rankings[[index]], continuing)
      value <- election$votes[index] * values[index]
      if (length(ranking)) {
        owners[index] <- ranking[1L]
        scores[ranking[1L]] <- scores[ranking[1L]] + value
      } else {
        exhausted <- exhausted + value
      }
    }
    history <- c(history, list(scores))
    row <- sprintf("round %d: %s; exhausted %s", length(history), value_list(election, continuing, scores, TRUE), money(exhausted))
    order <- ordered(election, continuing, scores)
    if (length(continuing) == seats - length(elected)) {
      elected <- c(elected, order)
      rows <- c(rows, paste0(row, "; elected ", name_list(election, order)))
      break
    }
    chosen <- order[1L]
    if (scores[chosen] >= quota) {
      surplus <- scores[chosen] - quota
      elected <- c(elected, chosen)
      continuing <- setdiff(continuing, chosen)
      indices <- which(owners == chosen)
      values[indices] <- (values[indices] * surplus) %/% scores[chosen]
      rows <- c(rows, paste0(row, "; elected ", election$names[chosen], " (surplus ", money(surplus), ")"))
      if (length(elected) == seats) break
    } else {
      choice <- look_back(election, continuing, history)
      continuing <- setdiff(continuing, choice$candidate)
      rows <- c(rows, paste0(row, "; excluded ", election$names[choice$candidate], tie_text(choice$tie)))
    }
  }
  list(order = integer(), rows = c(rows, paste0("elected: ", name_list(election, elected))))
}
tally <- function(election, field, method) {
  words <- strsplit(method, " ", fixed = TRUE)[[1L]]
  kind <- words[1L]
  if (kind == "RUNOFF") return(runoff(election, field))
  if (kind %in% c("IRV", "COOMBS")) return(elimination(election, field, kind == "COOMBS"))
  if (kind == "BUCKLIN") return(bucklin(election, field))
  if (kind %in% c("BALDWIN", "NANSON")) return(borda_elimination(election, field, kind == "NANSON"))
  if (kind == "CONDORCET") return(condorcet_report(election, field))
  if (kind == "SCHULZE") return(schulze(election, field))
  if (kind == "RANKEDPAIRS") return(ranked_pairs(election, field))
  if (kind == "KEMENY") return(kemeny(election, field))
  if (kind == "STV") return(stv(election, field, as.integer(words[2L])))
  base <- tallies(election, field)
  scores <- integer(length(election$names))
  label <- "scores"
  descending <- TRUE
  rows <- character()
  winner <- 0L
  if (kind == "PLURALITY") {
    scores <- base$first
    label <- "votes"
  } else if (kind %in% c("BORDA", "BLACK")) {
    scores <- base$borda
    if (kind == "BLACK") {
      winner <- condorcet(election, field)
      rows <- paste("condorcet:", if (winner == 0L) "NONE" else election$names[winner])
    }
  } else if (kind == "VETO") {
    scores <- base$last
    label <- "vetoes"
    descending <- FALSE
  } else if (kind == "APPROVAL") {
    scores <- base$approval[min(as.integer(words[2L]), length(field)), ]
    label <- "approvals"
  } else if (kind == "COPELAND") {
    matrix <- pairwise(election)
    parts <- character()
    for (candidate in field) {
      others <- setdiff(field, candidate)
      forward <- matrix[candidate, others]
      backward <- matrix[others, candidate]
      wins <- sum(forward > backward)
      draws <- sum(forward == backward)
      losses <- sum(forward < backward)
      scores[candidate] <- 2L * wins + draws
      score <- scores[candidate]
      parts <- c(parts, sprintf("%s %d.%d (%d-%d-%d)", election$names[candidate],
                                score %/% 2L, (score %% 2L) * 5L, wins, draws, losses))
    }
    rows <- paste0("scores: ", paste(parts, collapse = ", "))
  } else if (kind == "MINIMAX") {
    matrix <- pairwise(election)
    descending <- FALSE
    for (candidate in field) {
      others <- setdiff(field, candidate)
      opposition <- matrix[others, candidate]
      support <- matrix[candidate, others]
      values <- if (words[2L] == "OPPOSITION") opposition else
        if (words[2L] == "MARGIN") pmax.int(0L, opposition - support) else opposition * (opposition > support)
      scores[candidate] <- max(values)
    }
  }
  order <- ordered(election, field, scores, descending)
  tie <- scores[order[1L]] == scores[order[2L]]
  if (winner != 0L) {
    order <- c(winner, setdiff(order, winner))
    tie <- FALSE
  }
  if (kind != "COPELAND") rows <- c(rows, paste0(label, ": ", value_list(election, field, scores)))
  finish(election, order, tie, rows)
}
ballots_report <- function(election) {
  notation <- vapply(election$rankings, function(ranking) {
    ranking <- effective(ranking, which(election$active))
    if (length(ranking)) name_list(election, ranking, ">") else "-"
  }, character(1))
  distinct <- unique(notation)
  counts <- vapply(distinct, function(text) sum(election$votes[notation == text]), integer(1))
  order <- order(-counts, distinct, method = "radix")
  rows <- sprintf("total %d, blank %d, distinct %d", election$total, sum(election$votes[notation == "-"]), length(distinct))
  c(rows, paste(counts[order], distinct[order]))
}
status <- function(election) {
  withdrawn <- which(!election$active)
  c(paste("election", election$number), paste0("active: ", name_list(election, which(election$active))),
    paste0("withdrawn: ", if (length(withdrawn)) name_list(election, withdrawn) else "none"),
    paste0("tiebreak: ", name_list(election, election$tiebreak)),
    sprintf("ballots: %d in %d entries", election$total, length(election$ends)))
}
execute <- function(lab, line) {
  words <- strsplit(line, " ", fixed = TRUE)[[1L]]
  command <- words[1L]
  if (command == "CANDIDATES") {
    names <- words[-1L]
    if (length(names) == 1L) fail("too few candidates")
    duplicate <- which(duplicated(names))
    if (length(duplicate)) fail(paste("duplicate candidate", names[duplicate[1L]]))
    election <- new_election(lab$number + 1L, names)
    lab$number <- lab$number + 1L
    lab$current <- election
    return(sprintf("election %d: %d candidates", lab$number, length(names)))
  }
  election <- lab$current
  if (is.null(election)) fail("no election")
  if (command == "BALLOT") {
    ranking <- if (words[3L] == "-") integer() else checked_names(election, strsplit(words[3L], ">", fixed = TRUE)[[1L]])
    votes <- as.integer(words[2L])
    election$votes <- c(election$votes, votes)
    election$rankings <- c(election$rankings, list(ranking))
    election$total <- election$total + votes
    election$ends <- c(election$ends, length(election$votes))
    election$cache <- new.env(parent = emptyenv())
    lab$current <- election
    return(character())
  } else if (command == "RANDOM") {
    count <- as.integer(words[2L])
    state <- as.bigz(words[3L])
    for (group in seq_len(count)) {
      ranking <- which(election$active)
      for (size in rev(seq_len(length(ranking) - 1L) + 1L)) {
        state <- (48271L * state) %% 2147483647L
        index <- as.integer(state %% size) + 1L
        ranking[c(size, index)] <- ranking[c(index, size)]
      }
      state <- (48271L * state) %% 2147483647L
      ranking <- ranking[seq_len(as.integer(state %% length(ranking)) + 1L)]
      election$votes <- c(election$votes, 1L)
      election$rankings <- c(election$rankings, list(ranking))
    }
    election$total <- election$total + count
    election$ends <- c(election$ends, length(election$votes))
    election$cache <- new.env(parent = emptyenv())
    lab$current <- election
    return(character())
  } else if (command == "UNDO") {
    if (!length(election$ends)) fail("nothing to undo")
    election$ends <- head(election$ends, -1L)
    end <- tail(c(0L, election$ends), 1L)
    election$votes <- election$votes[seq_len(end)]
    election$rankings <- election$rankings[seq_len(end)]
    election$total <- sum(election$votes)
    election$cache <- new.env(parent = emptyenv())
    lab$current <- election
    return(character())
  } else if (command %in% c("WITHDRAW", "RESTORE")) {
    candidate <- candidate_index(election, words[2L])
    if (command == "WITHDRAW") {
      if (!election$active[candidate]) fail(paste("already withdrawn", words[2L]))
      if (sum(election$active) <= 2L) fail("too few candidates")
      election$active[candidate] <- FALSE
    } else {
      if (election$active[candidate]) fail(paste("not withdrawn", words[2L]))
      election$active[candidate] <- TRUE
    }
    lab$current <- election
    return(character())
  } else if (command == "TIEBREAK") {
    order <- checked_names(election, words[-1L])
    if (length(order) != length(election$names)) fail("incomplete tiebreak")
    election$tiebreak <- order
    election$priority <- match(seq_along(election$names), order)
    lab$current <- election
    return(character())
  }
  heading <- paste0("[", line, "]")
  if (command == "STATUS") return(c(heading, status(election)))
  if (!length(election$ends)) fail("no ballots")
  field <- which(election$active)
  if (command %in% c("RANKING", "SPOILERS")) {
    method <- paste(words[-1L], collapse = " ")
    if (words[2L] %in% c("CONDORCET", "STV")) fail("not rankable")
    if (command == "SPOILERS" && length(field) < 3L) fail("too few candidates")
    result <- tally(election, field, method)
    if (command == "RANKING") return(c(heading, name_list(election, result$order, " > ")))
    winner <- result$order[1L]
    rows <- paste0("winner: ", election$names[winner])
    for (candidate in setdiff(field, winner)) {
      other <- tally(election, setdiff(field, candidate), method)$order[1L]
      rows <- c(rows, paste0("without ", election$names[candidate], ": ", election$names[other],
                             if (other != winner) " (changed)" else ""))
    }
    return(c(heading, rows))
  }
  compared <- integer()
  if (command == "COMPARE") {
    for (name in words[-1L]) {
      candidate <- candidate_index(election, name)
      if (!election$active[candidate]) fail(paste("withdrawn candidate", name))
      compared <- c(compared, candidate)
    }
    if (compared[1L] == compared[2L]) fail("same candidate")
  }
  if (command == "STV" && as.integer(words[2L]) >= length(field)) fail("too many seats")
  rows <- switch(command,
    BALLOTS = ballots_report(election),
    PROFILE = {
      scores <- tallies(election, field)
      vapply(field, function(candidate) {
        cumulative <- scores$approval[, candidate]
        counts <- cumulative - c(0L, head(cumulative, -1L))
        sprintf("%s: %s unranked %d", election$names[candidate], paste(counts, collapse = " "), election$total - tail(cumulative, 1L))
      }, character(1))
    },
    PAIRWISE = pair_lines(election, field, pairwise(election)),
    EXHAUSTED = elimination(election, field, exhausted = TRUE)$rows,
    SUMMARY = NULL,
    COMPARE = NULL,
    tally(election, field, line)$rows
  )
  if (command %in% c("SUMMARY", "COMPARE")) {
    rows <- character()
    wins <- integer(length(election$names))
    ahead <- list(character(), character())
    for (method in summary_methods) {
      result <- tally(election, field, method)
      if (command == "SUMMARY") {
        winner <- result$order[1L]
        wins[winner] <- wins[winner] + 1L
        rows <- c(rows, paste0(method, ": ", election$names[winner]))
      } else {
        side <- if (match(compared[1L], result$order) < match(compared[2L], result$order)) 1L else 2L
        ahead[[side]] <- c(ahead[[side]], method)
      }
    }
    if (command == "SUMMARY") {
      rows <- c(rows, paste0("wins: ", value_list(election, field, wins)))
    } else {
      matrix <- pairwise(election)
      first <- compared[1L]
      second <- compared[2L]
      forward <- matrix[first, second]
      backward <- matrix[second, first]
      rows <- sprintf("%s %d, %s %d, neither %d", election$names[first], forward,
                      election$names[second], backward, election$total - forward - backward)
      for (side in 1:2) {
        rows <- c(rows, paste0(election$names[compared[side]], " ahead: ",
                               if (length(ahead[[side]])) paste(ahead[[side]], collapse = ", ") else "none"))
      }
    }
  }
  c(heading, rows)
}
main <- function() {
  input <- readLines(file("stdin"), warn = FALSE)
  lab <- new.env(parent = emptyenv())
  lab$number <- 0L
  lab$current <- NULL
  for (index in seq_len(as.integer(input[1L]))) {
    rows <- tryCatch(execute(lab, input[index + 1L]),
                     command_error = function(problem) paste("ERROR", conditionMessage(problem)))
    if (length(rows)) cat(paste(rows, collapse = "\n"), "\n", sep = "")
  }
}
main()
