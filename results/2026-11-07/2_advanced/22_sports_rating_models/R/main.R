source("season.R")
source("report.R")
source("elo.R")
source("linear_models.R")
source("iterative_models.R")
source("evaluation.R")

rating_models <- c("elo", "colley", "massey", "bt", "od", "winpct")
comparison_models <- c("standings", "elo", "colley", "massey", "bt", "od", "winpct", "rpi", "pythag")
link_models <- c("colley", "massey", "od", "winpct")
prediction_models <- c("base", "elo", "colley", "massey", "bt", "od", "winpct", "ensemble")
standings_header <- "pos,team,name,played,won,drawn,lost,scored,conceded,diff,points,home,away,form,streak,close,longest_win,longest_unbeaten,winpct,sos,sos2,rpi,pythag,luck"
ratings_header <- "team,elo,elo_rank,colley,colley_rank,massey,massey_rank,bt,bt_rank,offense,defense,od,od_rank,winpct,winpct_rank,consensus,best_rank,worst_rank"
history_header <- "round,team,elo,change,elo_rank,points,position"
projection_header <- "projected,team,points_now,position_now,remaining_opponent_elo,expected_points,title,top,bottom,final_points,final_position"

sequential_sum <- function(values) {
  total <- 0
  for (value in values) total <- total + value
  total
}
mean_ordered <- function(values) sequential_sum(values) / length(values)
count_text <- function(value) sprintf("%.0f", value)
csv_line <- function(fields) paste(vapply(fields, function(value) if (is.numeric(value)) count_text(value) else as.character(value), character(1)), collapse = ",")
join_parts <- function(parts) {
  lines <- character()
  for (part in parts) {
    if (length(lines) > 0L) lines <- c(lines, "")
    lines <- c(lines, part)
  }
  lines
}
competition_ranks <- function(values) vapply(values, function(value) {
  1L + sum(vapply(values, function(other) fraction_compare(other, value) > 0, logical(1)))
}, integer(1))
rounded_values <- function(values, places) lapply(values, function(value) fraction(decimal_value(value, places)))
negative_values <- function(values) lapply(values, function(value) fraction(-value))
result_letter <- function(scored, conceded) if (scored > conceded) "W" else if (scored == conceded) "D" else "L"
result_code <- function(result2) if (result2 == 2L) "H" else if (result2 == 0L) "A" else "D"
appearances_of <- function(team, matches) {
  lapply(Filter(function(match) match$home == team || match$away == team, matches), function(match) {
    home <- match$home == team
    scored <- if (home) match$home_score else match$away_score
    conceded <- if (home) match$away_score else match$home_score
    list(match = match, home = home, opponent = if (home) match$away else match$home,
         scored = scored, conceded = conceded, letter = result_letter(scored, conceded))
  })
}
record_text <- function(items) {
  letters <- vapply(items, function(item) item$letter, character(1))
  sprintf("%d-%d-%d", sum(letters == "W"), sum(letters == "D"), sum(letters == "L"))
}
team_records <- function(count, matches, settings) {
  records <- matrix(0, count, 7L, dimnames = list(NULL, c("played", "won", "drawn", "lost", "scored", "conceded", "points")))
  for (match in matches) {
    for (home in c(TRUE, FALSE)) {
      team <- if (home) match$home else match$away
      scored <- if (home) match$home_score else match$away_score
      conceded <- if (home) match$away_score else match$home_score
      records[team, "played"] <- records[team, "played"] + 1
      records[team, "scored"] <- records[team, "scored"] + scored
      records[team, "conceded"] <- records[team, "conceded"] + conceded
      if (scored > conceded) {
        records[team, "won"] <- records[team, "won"] + 1
        records[team, "points"] <- records[team, "points"] + settings$win_points
      } else if (scored == conceded) {
        records[team, "drawn"] <- records[team, "drawn"] + 1
        records[team, "points"] <- records[team, "points"] + settings$draw_points
      } else records[team, "lost"] <- records[team, "lost"] + 1
    }
  }
  records
}
win_percentages <- function(records) lapply(seq_len(nrow(records)), function(team) {
  fraction(2 * records[team, "won"] + records[team, "drawn"], 2 * records[team, "played"])
})
make_standings <- function(teams, matches, settings) {
  count <- length(teams)
  records <- team_records(count, matches, settings)
  h2h_points <- h2h_difference <- numeric(count)
  for (match in matches) {
    i <- match$home
    j <- match$away
    if (records[i, "points"] != records[j, "points"]) next
    h2h_difference[i] <- h2h_difference[i] + match$margin
    h2h_difference[j] <- h2h_difference[j] - match$margin
    if (match$margin > 0L) {
      h2h_points[i] <- h2h_points[i] + settings$win_points
    } else if (match$margin < 0L) {
      h2h_points[j] <- h2h_points[j] + settings$win_points
    } else {
      h2h_points[i] <- h2h_points[i] + settings$draw_points
      h2h_points[j] <- h2h_points[j] + settings$draw_points
    }
  }
  order <- order(-records[, "points"], -h2h_points, -h2h_difference,
    -(records[, "scored"] - records[, "conceded"]), -records[, "scored"],
    vapply(teams, function(team) team$code, character(1)), method = "radix")
  positions <- integer(count)
  positions[order] <- seq_len(count)
  list(records = records, h2h_points = h2h_points, h2h_difference = h2h_difference, order = order, positions = positions)
}
tied_groups <- function(table) {
  groups <- list()
  for (team in table$order) {
    if (length(groups) > 0L && table$records[groups[[length(groups)]][1L], "points"] == table$records[team, "points"]) {
      groups[[length(groups)]] <- c(groups[[length(groups)]], team)
    } else groups[[length(groups) + 1L]] <- team
  }
  Filter(function(group) length(group) > 1L, groups)
}
longest_streak <- function(items, unbeaten) {
  best <- list(length = 0L, first = 0L, last = 0L)
  start <- length <- 0L
  for (i in seq_along(items)) {
    if (items[[i]]$letter != "W" && !(unbeaten && items[[i]]$letter == "D")) {
      length <- 0L
      next
    }
    if (length == 0L) start <- i
    length <- length + 1L
    if (length > best$length) best <- list(length = length, first = items[[start]]$match$round, last = items[[i]]$match$round)
  }
  best
}
current_streak <- function(items) {
  letter <- items[[length(items)]]$letter
  count <- 0L
  for (item in rev(items)) {
    if (item$letter != letter) break
    count <- count + 1L
  }
  paste0(letter, count)
}
fit_models <- function(count, matches, settings) {
  massey <- massey_ratings(count, matches)
  bt <- bradley_terry(count, matches, settings$bt_iterations)
  od <- offense_defense(count, matches, settings$od_iterations)
  list(elo = run_elo(count, matches, settings$elo_k, settings$elo_home, settings$elo_initial), colley = colley_ratings(count, matches),
       massey = massey$ratings, home_advantage = massey$home_advantage, strengths = bt$strengths, home_factor = bt$home_factor,
       offense = od$offense, defense = od$defense, od = od$od, win_percentages = win_percentages(team_records(count, matches, settings)))
}
feature <- function(fit, model, match) {
  i <- match$home
  j <- match$away
  if (model == "colley") return(fit$colley[i] - fit$colley[j])
  if (model == "massey") return(fit$massey[i] - fit$massey[j])
  if (model == "od") return(log(fit$od[i]) - log(fit$od[j]))
  fraction_real(fit$win_percentages[[i]]) - fraction_real(fit$win_percentages[[j]])
}
make_prediction <- function(match, probabilities, margin_error) {
  list(match = match, probabilities = probabilities, margin_error = margin_error,
       losses = vapply(probabilities, log_loss, numeric(1), result2 = match$result2),
       briers = vapply(probabilities, brier_score, numeric(1), y = match$y),
       scores2 = vapply(probabilities, correctness2, integer(1), result2 = match$result2))
}
make_validation <- function(number, count, matches, settings) {
  training <- matches_before(matches, number)
  fit <- fit_models(count, training, settings)
  results <- vapply(training, function(match) match$y, numeric(1))
  base <- sum(vapply(training, function(match) match$result2, integer(1))) / (2 * length(training))
  links <- setNames(lapply(link_models, function(model) fit_link(vapply(training, function(match) feature(fit, model, match), numeric(1)), results, settings$link_iterations)), link_models)
  predictions <- list()
  for (match in matches) {
    if (match$round != number) next
    probabilities <- setNames(numeric(8L), prediction_models)
    probabilities["base"] <- base
    probabilities["elo"] <- expected_score(fit$elo$ratings[match$home], fit$elo$ratings[match$away], settings$elo_home)
    home <- fit$home_factor * fit$strengths[match$home]
    probabilities["bt"] <- home / (home + fit$strengths[match$away])
    for (model in link_models) probabilities[model] <- sigma(links[[model]][1L] + links[[model]][2L] * feature(fit, model, match))
    probabilities["ensemble"] <- sequential_sum(probabilities[c("elo", "colley", "massey", "bt", "od", "winpct")]) / 6
    margin <- fit$massey[match$home] - fit$massey[match$away] + fit$home_advantage
    predictions[[length(predictions) + 1L]] <- make_prediction(match, probabilities, match$margin - margin)
  }
  list(number = number, training = training, fit = fit, base = base, links = links, predictions = predictions)
}
score_models <- function(predictions) {
  losses <- briers <- skills <- numeric(8L)
  accuracies <- list()
  scores2 <- numeric(8L)
  for (k in seq_len(8L)) {
    losses[k] <- mean_ordered(vapply(predictions, function(item) item$losses[k], numeric(1)))
    briers[k] <- mean_ordered(vapply(predictions, function(item) item$briers[k], numeric(1)))
    scores2[k] <- sum(vapply(predictions, function(item) item$scores2[k], integer(1)))
    accuracies[[k]] <- fraction(scores2[k], 2 * length(predictions))
  }
  skills <- 1 - briers / briers[1L]
  list(losses = losses, briers = briers, skills = skills, accuracies = accuracies,
       loss_ranking = order(decimal_value(losses, 4L), seq_len(8L), method = "radix"),
       brier_ranking = order(decimal_value(briers, 4L), seq_len(8L), method = "radix"),
       accuracy_ranking = order(-scores2, seq_len(8L), method = "radix"))
}
make_projection <- function(teams, matches, settings) {
  count <- length(teams)
  current_matches <- matches_before(matches, settings$holdout)
  current <- make_standings(teams, current_matches, settings)
  ratings <- run_elo(count, current_matches, settings$elo_k, settings$elo_home, settings$elo_initial)$ratings
  remaining <- Filter(function(match) match$round >= settings$holdout, matches)
  probabilities <- vapply(remaining, function(match) expected_score(ratings[match$home], ratings[match$away], settings$elo_home), numeric(1))
  total_points <- titles <- tops <- bottoms <- numeric(count)
  rank_order <- function(points) order(-points, current$positions, method = "radix")
  state <- settings$seed
  for (simulation in seq_len(settings$simulations)) {
    points <- current$records[, "points"] + 0
    for (i in seq_along(remaining)) {
      match <- remaining[[i]]
      state <- (48271 * state) %% 2147483647
      winner <- if (state / 2147483647 < probabilities[i]) match$home else match$away
      points[winner] <- points[winner] + settings$win_points
    }
    order <- rank_order(points)
    for (place in seq_along(order)) {
      team <- order[place]
      total_points[team] <- total_points[team] + points[team]
      if (place == 1L) titles[team] <- titles[team] + 1
      if (place <= settings$top) tops[team] <- tops[team] + 1
      if (place >= count - settings$bottom + 1L) bottoms[team] <- bottoms[team] + 1
    }
  }
  order <- rank_order(total_points)
  ranks <- integer(count)
  ranks[order] <- seq_len(count)
  list(current = current, ratings = ratings, remaining = remaining, total_points = total_points,
       titles = titles, tops = tops, bottoms = bottoms, order = order, ranks = ranks)
}
opponent_strength <- function(projection, team) {
  values <- numeric()
  for (match in projection$remaining) {
    if (match$home == team) values <- c(values, projection$ratings[match$away])
    else if (match$away == team) values <- c(values, projection$ratings[match$home])
  }
  mean_ordered(values)
}
make_analysis <- function(teams, matches, settings) {
  count <- length(teams)
  final_round <- matches[[length(matches)]]$round
  appearances <- lapply(seq_len(count), appearances_of, matches = matches)
  final <- make_standings(teams, matches, settings)
  fit <- fit_models(count, matches, settings)
  round_tables <- lapply(seq_len(final_round), function(number) make_standings(teams, matches_before(matches, number + 1L), settings))
  win_streaks <- lapply(appearances, longest_streak, unbeaten = FALSE)
  unbeaten_streaks <- lapply(appearances, longest_streak, unbeaten = TRUE)
  opponent_average <- function(team, values) {
    total <- fraction(0)
    for (appearance in appearances[[team]]) total <- fraction_add(total, values[[appearance$opponent]])
    fraction_divide(total, length(appearances[[team]]))
  }
  sos <- lapply(seq_len(count), opponent_average, values = fit$win_percentages)
  sos2 <- lapply(seq_len(count), opponent_average, values = sos)
  rpi <- lapply(seq_len(count), function(team) fraction_divide(fraction_add(fraction_add(fit$win_percentages[[team]], fraction_multiply(fraction(2), sos[[team]])), sos2[[team]]), 4))
  pythag <- 1 / (1 + (final$records[, "conceded"] / final$records[, "scored"]) ^ settings$exponent)
  luck <- vapply(fit$win_percentages, fraction_real, numeric(1)) - pythag
  comparison <- list(standings = negative_values(final$positions), elo = rounded_values(fit$elo$ratings, 2L),
    colley = rounded_values(fit$colley, 4L), massey = rounded_values(fit$massey, 4L), bt = rounded_values(fit$strengths, 4L),
    od = rounded_values(fit$od, 2L), winpct = fit$win_percentages, rpi = rpi, pythag = rounded_values(pythag, 4L))
  ranks <- setNames(lapply(rating_models, function(model) competition_ranks(comparison[[model]])), rating_models)
  rounds <- lapply(seq.int(settings$holdout, final_round), make_validation, count = count, matches = matches, settings = settings)
  predictions <- unlist(lapply(rounds, function(round) round$predictions), recursive = FALSE, use.names = FALSE)
  list(teams = teams, matches = matches, settings = settings, count = count, final_round = final_round,
    appearances = appearances, final = final, fit = fit, round_tables = round_tables, win_streaks = win_streaks,
    unbeaten_streaks = unbeaten_streaks, sos = sos, sos2 = sos2, rpi = rpi, pythag = pythag, luck = luck, comparison = comparison,
    ranks = ranks, rounds = rounds, predictions = predictions, scores = score_models(predictions), projection = make_projection(teams, matches, settings))
}
code <- function(a, team) a$teams[[team]]$code

standings_lines <- function(a) {
  lines <- standings_header
  for (position in seq_along(a$final$order)) {
    team <- a$final$order[position]
    record <- a$final$records[team, ]
    items <- a$appearances[[team]]
    home <- Filter(function(item) item$home, items)
    away <- Filter(function(item) !item$home, items)
    close <- Filter(function(item) abs(item$scored - item$conceded) <= a$settings$close_margin, items)
    form <- paste0(vapply(tail(items, a$settings$form_length), function(item) item$letter, character(1)), collapse = "")
    lines <- c(lines, csv_line(c(list(position, code(a, team), a$teams[[team]]$name), as.list(record[c("played", "won", "drawn", "lost", "scored", "conceded")]),
      list(record["scored"] - record["conceded"], record["points"], record_text(home), record_text(away), form, current_streak(items), record_text(close),
        a$win_streaks[[team]]$length, a$unbeaten_streaks[[team]]$length, fraction_text(a$fit$win_percentages[[team]]), fixed_fraction(a$sos[[team]]),
        fixed_fraction(a$sos2[[team]]), fixed_fraction(a$rpi[[team]]), fixed(a$pythag[team]), fixed(a$luck[team])))))
  }
  lines
}
ratings_lines <- function(a) {
  totals <- vapply(seq_len(a$count), function(team) sum(vapply(a$ranks, function(values) values[team], integer(1))), integer(1))
  ordered <- order(totals, vapply(a$teams, function(team) team$code, character(1)), method = "radix")
  f <- a$fit
  lines <- ratings_header
  for (team in ordered) {
    ranks <- vapply(a$ranks, function(values) values[team], integer(1))
    lines <- c(lines, csv_line(list(code(a, team), fixed(f$elo$ratings[team], 2L), ranks["elo"], fixed(f$colley[team]), ranks["colley"],
      fixed(f$massey[team]), ranks["massey"], fixed(f$strengths[team]), ranks["bt"], fixed(f$offense[team], 2L), fixed(f$defense[team]),
      fixed(f$od[team], 2L), ranks["od"], fixed_fraction(f$win_percentages[[team]]), ranks["winpct"], totals[team], min(ranks), max(ranks))))
  }
  lines
}
history_lines <- function(a) {
  lines <- history_header
  previous <- rep(a$settings$elo_initial, a$count)
  for (number in seq_len(a$final_round)) {
    ratings <- a$fit$elo$rounds[[number]]
    ranks <- competition_ranks(rounded_values(ratings, 2L))
    table <- a$round_tables[[number]]
    for (team in seq_len(a$count)) lines <- c(lines, csv_line(list(number, code(a, team), fixed(ratings[team], 2L), fixed(ratings[team] - previous[team], 2L),
      ranks[team], table$records[team, "points"], table$positions[team])))
    previous <- ratings
  }
  lines
}
summary_lines <- function(a) {
  results <- vapply(a$matches, function(match) match$result2, integer(1))
  c(sprintf("season teams %d matches %d rounds %d", a$count, length(a$matches), a$final_round),
    sprintf("home won %d drawn %d lost %d rate %s", sum(results == 2L), sum(results == 1L), sum(results == 0L), fraction_with_real(fraction(sum(results), 2 * length(results)))),
    paste("massey_home_advantage", fixed(a$fit$home_advantage)), paste("bt_home_factor", fixed(a$fit$home_factor)))
}
upset_lines <- function(a) {
  candidates <- list()
  for (i in seq_along(a$matches)) {
    match <- a$matches[[i]]
    if (match$margin == 0L) next
    expected <- if (match$margin > 0L) a$fit$elo$expected[i] else 1 - a$fit$elo$expected[i]
    candidates[[length(candidates) + 1L]] <- list(index = i, expected = expected, gain = abs(a$fit$elo$changes[i]))
  }
  ordered <- order(vapply(candidates, function(item) decimal_value(item$expected, 4L), numeric(1)), seq_along(candidates), method = "radix")
  lines <- paste("upsets top", count_text(a$settings$upsets))
  for (index in head(ordered, min(a$settings$upsets, length(ordered)))) {
    item <- candidates[[index]]
    match <- a$matches[[item$index]]
    home <- match$margin > 0L
    winner <- if (home) match$home else match$away
    loser <- if (home) match$away else match$home
    score <- if (home) paste0(match$home_score, "-", match$away_score) else paste0(match$away_score, "-", match$home_score)
    lines <- c(lines, sprintf("round %d %s beat %s %s %s expected %s gain %s", match$round, code(a, winner), code(a, loser), score,
      if (home) "home" else "away", fixed(item$expected), fixed(item$gain, 2L)))
  }
  lines
}
tiebreak_lines <- function(a) {
  lines <- "tiebreaks"
  for (group in tied_groups(a$final)) {
    lines <- c(lines, paste("points", count_text(a$final$records[group[1L], "points"]), "order", paste(vapply(group, function(team) code(a, team), character(1)), collapse = " "),
      "h2h_points", paste(count_text(a$final$h2h_points[group]), collapse = " "), "h2h_diff", paste(count_text(a$final$h2h_difference[group]), collapse = " ")))
  }
  if (length(lines) == 1L) lines <- c(lines, "none")
  lines
}
leader_lines <- function(a) {
  lines <- "leaders"
  previous <- 0L
  recorded <- 0L
  for (number in seq_len(a$final_round)) {
    table <- a$round_tables[[number]]
    leader <- table$order[1L]
    if (leader != previous) {
      lines <- c(lines, sprintf("round %d %s points %s", number, code(a, leader), count_text(table$records[leader, "points"])))
      recorded <- recorded + 1L
    }
    previous <- leader
  }
  c(lines, paste("lead_changes", recorded - 1L))
}
streak_lines <- function(a) {
  lines <- character()
  for (label in c("longest_win_streak", "longest_unbeaten_streak")) {
    streaks <- if (label == "longest_win_streak") a$win_streaks else a$unbeaten_streaks
    longest <- max(vapply(streaks, function(streak) streak$length, integer(1)))
    for (team in seq_len(a$count)) {
      streak <- streaks[[team]]
      if (streak$length == longest) lines <- c(lines, sprintf("%s %s length %d rounds %d-%d", label, code(a, team), streak$length, streak$first, streak$last))
    }
  }
  lines
}
crosstable_lines <- function(a) {
  top <- head(a$final$order, a$settings$top)
  lines <- c(paste("crosstable top", count_text(a$settings$top)), paste("team", paste(vapply(top, function(team) code(a, team), character(1)), collapse = " ")))
  for (first in top) {
    entries <- vapply(top, function(second) {
      if (first == second) "-" else record_text(Filter(function(item) item$opponent == second, a$appearances[[first]]))
    }, character(1))
    lines <- c(lines, paste(code(a, first), paste(entries, collapse = " ")))
  }
  lines
}
trajectory_lines <- function(a) {
  lines <- "trajectories"
  for (team in seq_len(a$count)) {
    ratings <- vapply(a$fit$elo$rounds, function(snapshot) snapshot[team], numeric(1))
    rounded <- decimal_value(ratings, 2L)
    positions <- vapply(a$round_tables, function(table) table$positions[team], integer(1))
    peak <- low <- best <- worst <- 1L
    for (r in seq.int(2L, a$final_round)) {
      if (rounded[r] > rounded[peak]) peak <- r
      if (rounded[r] < rounded[low]) low <- r
      if (positions[r] < positions[best]) best <- r
      if (positions[r] > positions[worst]) worst <- r
    }
    lines <- c(lines, sprintf("%s elo_peak %s round %d elo_low %s round %d best_position %d round %d worst_position %d round %d", code(a, team),
      fixed(ratings[peak], 2L), peak, fixed(ratings[low], 2L), low, positions[best], best, positions[worst], worst))
  }
  lines
}
correlation_lines <- function(a, title, measure) {
  lines <- c(title, paste("model", paste(comparison_models, collapse = " ")))
  for (first in comparison_models) {
    values <- vapply(comparison_models, function(second) fraction_text(measure(a$comparison[[first]], a$comparison[[second]])), character(1))
    lines <- c(lines, paste(first, paste(values, collapse = " ")))
  }
  lines
}
similarity_lines <- function(a) {
  most <- least <- NULL
  for (i in seq_len(length(comparison_models) - 1L)) for (j in seq.int(i + 1L, length(comparison_models))) {
    first <- comparison_models[i]
    second <- comparison_models[j]
    tau <- kendall_tau(a$comparison[[first]], a$comparison[[second]])
    candidate <- list(first = first, second = second, tau = tau)
    if (is.null(most) || fraction_compare(tau, most$tau) > 0) most <- candidate
    if (is.null(least) || fraction_compare(tau, least$tau) < 0) least <- candidate
  }
  c(paste("most_similar", most$first, most$second, "tau", fraction_with_real(most$tau)),
    paste("least_similar", least$first, least$second, "tau", fraction_with_real(least$tau)))
}
season_lines <- function(a) join_parts(list(summary_lines(a), upset_lines(a), tiebreak_lines(a), leader_lines(a), streak_lines(a), crosstable_lines(a),
  trajectory_lines(a), correlation_lines(a, "kendall", kendall_tau), correlation_lines(a, "spearman", spearman_rho), similarity_lines(a)))
prediction_lines <- function(a) {
  lines <- paste0("round,home,away,home_score,away_score,result,", paste(prediction_models, collapse = ","))
  for (item in a$predictions) {
    match <- item$match
    fields <- c(list(match$round, code(a, match$home), code(a, match$away), match$home_score, match$away_score, result_code(match$result2)), as.list(vapply(item$probabilities, fixed, character(1))))
    lines <- c(lines, csv_line(fields))
  }
  lines
}
link_lines <- function(a) {
  lines <- "links"
  for (round in a$rounds) {
    line <- sprintf("round %d train %d base %s bt_home %s", round$number, length(round$training), fixed(round$base), fixed(round$fit$home_factor))
    for (model in link_models) line <- paste(line, model, fixed(round$links[[model]][1L]), fixed(round$links[[model]][2L]))
    lines <- c(lines, line)
  }
  lines
}
score_lines <- function(a) {
  scores <- a$scores
  lines <- c("scores", "model log_loss brier skill accuracy")
  for (k in seq_len(8L)) lines <- c(lines, paste(prediction_models[k], fixed(scores$losses[k]), fixed(scores$briers[k]), fixed(scores$skills[k]), fraction_with_real(scores$accuracies[[k]])))
  c(lines, paste("ranking_log_loss", paste(prediction_models[scores$loss_ranking], collapse = " ")),
    paste("ranking_brier", paste(prediction_models[scores$brier_ranking], collapse = " ")),
    paste("ranking_accuracy", paste(prediction_models[scores$accuracy_ranking], collapse = " ")))
}
paired_lines <- function(a) {
  reference <- a$scores$loss_ranking[1L]
  count <- length(a$predictions)
  lines <- paste("paired_log_loss reference", prediction_models[reference])
  for (k in seq_len(8L)) {
    if (k == reference) next
    deltas <- vapply(a$predictions, function(item) item$losses[k] - item$losses[reference], numeric(1))
    average <- mean_ordered(deltas)
    squares <- sequential_sum((deltas - average) * (deltas - average))
    spread <- sqrt(squares / (count - 1L))
    t_value <- average / (spread / sqrt(count))
    lines <- c(lines, paste(prediction_models[k], "mean_diff", fixed(average), "sd", fixed(spread), "t", fixed(t_value, 2L)))
  }
  lines
}
margin_lines <- function(a) {
  errors <- vapply(a$predictions, function(item) item$margin_error, numeric(1))
  paste("massey_margin mae", fixed(mean_ordered(abs(errors))), "rmse", fixed(sqrt(mean_ordered(errors * errors))), "bias", fixed(mean_ordered(errors)))
}
round_loss_lines <- function(a) {
  lines <- c("round_log_loss", paste("round", paste(prediction_models, collapse = " ")))
  for (round in a$rounds) {
    values <- vapply(seq_len(8L), function(k) fixed(mean_ordered(vapply(round$predictions, function(item) item$losses[k], numeric(1)))), character(1))
    lines <- c(lines, paste(round$number, paste(values, collapse = " ")))
  }
  lines
}
calibration_lines <- function(a) {
  bins <- a$settings$bins
  lines <- paste("calibration bins", count_text(bins))
  for (k in seq_len(8L)) {
    members <- vector("list", bins)
    for (item in a$predictions) {
      number <- min(floor(bins * item$probabilities[k]) + 1L, bins)
      members[[number]] <- c(members[[number]], list(item))
    }
    for (number in seq_len(bins)) {
      group <- members[[number]]
      prefix <- sprintf("%s bin %d count %d predicted", prediction_models[k], number, length(group))
      if (length(group) == 0L) {
        lines <- c(lines, paste(prefix, "- observed -"))
      } else {
        predicted <- mean_ordered(vapply(group, function(item) item$probabilities[k], numeric(1)))
        observed <- fraction(sum(vapply(group, function(item) item$match$result2, integer(1))), 2 * length(group))
        lines <- c(lines, paste(prefix, fixed(predicted), "observed", fraction_text(observed)))
      }
    }
  }
  lines
}
grid_lines <- function(a) {
  settings <- a$settings
  lines <- c("elo_grid", paste("k", paste0("h", count_text(settings$grid_home), collapse = " ")))
  best <- NULL
  for (k in settings$grid_k) {
    row <- count_text(k)
    for (home in settings$grid_home) {
      run <- run_elo(a$count, a$matches, k, home, settings$elo_initial)
      losses <- numeric()
      for (i in seq_along(a$matches)) if (a$matches[[i]]$round >= settings$holdout) losses <- c(losses, log_loss(run$expected[i], a$matches[[i]]$result2))
      loss <- mean_ordered(losses)
      row <- c(row, fixed(loss))
      if (is.null(best) || decimal_value(loss, 4L) < decimal_value(best$loss, 4L)) best <- list(k = k, home = home, loss = loss)
    }
    lines <- c(lines, paste(row, collapse = " "))
  }
  c(lines, paste("best k", count_text(best$k), "home", count_text(best$home), "log_loss", fixed(best$loss)))
}
projection_tau <- function(a) kendall_tau(negative_values(a$projection$ranks), negative_values(a$final$positions))
evaluation_lines <- function(a) join_parts(list(sprintf("holdout rounds %d-%d matches %d", a$settings$holdout, a$final_round, length(a$predictions)),
  link_lines(a), score_lines(a), paired_lines(a), margin_lines(a), round_loss_lines(a), calibration_lines(a), grid_lines(a),
  paste("projection simulations", count_text(a$settings$simulations), "kendall", fraction_with_real(projection_tau(a)))))
projection_lines <- function(a) {
  p <- a$projection
  simulations <- a$settings$simulations
  lines <- projection_header
  for (rank in seq_along(p$order)) {
    team <- p$order[rank]
    lines <- c(lines, csv_line(list(rank, code(a, team), p$current$records[team, "points"], p$current$positions[team], fixed(opponent_strength(p, team), 2L),
      fixed_fraction(fraction(p$total_points[team], simulations)), fixed_fraction(fraction(p$titles[team], simulations)), fixed_fraction(fraction(p$tops[team], simulations)), fixed_fraction(fraction(p$bottoms[team], simulations)),
      a$final$records[team, "points"], a$final$positions[team])))
  }
  lines
}

main <- function() {
  season <- load_season()
  analysis <- make_analysis(season$teams, season$matches, season$settings)
  dir.create("output", showWarnings = FALSE)
  write_lines("standings.csv", standings_lines(analysis))
  write_lines("ratings.csv", ratings_lines(analysis))
  write_lines("history.csv", history_lines(analysis))
  write_lines("season.txt", season_lines(analysis))
  write_lines("predictions.csv", prediction_lines(analysis))
  write_lines("evaluation.txt", evaluation_lines(analysis))
  write_lines("projection.csv", projection_lines(analysis))
}

main()
