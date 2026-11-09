read_lines <- function(path) readLines(path, warn = FALSE)
match_result2 <- function(home, away) if (home > away) 2L else if (home == away) 1L else 0L
matches_before <- function(matches, round) Filter(function(match) match$round < round, matches)

load_season <- function() {
  teams <- lapply(read_lines("input/teams.csv")[-1L], function(line) {
    fields <- strsplit(line, ",", fixed = TRUE)[[1L]]
    list(code = fields[1L], name = fields[2L])
  })
  codes <- vapply(teams, function(team) team$code, character(1))
  matches <- lapply(read_lines("input/matches.csv")[-1L], function(line) {
    fields <- strsplit(line, ",", fixed = TRUE)[[1L]]
    home <- as.integer(fields[4L])
    away <- as.integer(fields[5L])
    list(round = as.integer(fields[1L]), home = match(fields[2L], codes), away = match(fields[3L], codes),
         home_score = home, away_score = away, margin = home - away, result2 = match_result2(home, away), y = match_result2(home, away) / 2)
  })
  matches <- matches[order(vapply(matches, function(match) match$round, integer(1)), seq_along(matches), method = "radix")]
  rows <- strsplit(read_lines("input/params.txt"), " ", fixed = TRUE)
  values <- setNames(lapply(rows, function(row) row[-1L]), vapply(rows, function(row) row[1L], character(1)))
  value <- function(key) as.numeric(values[[key]])
  settings <- list(win_points = value("WIN_POINTS"), draw_points = value("DRAW_POINTS"), form_length = value("FORM_LENGTH"),
    close_margin = value("CLOSE_MARGIN"), exponent = value("PYTHAGOREAN_EXPONENT"), elo_k = value("ELO_K"),
    elo_home = value("ELO_HOME"), elo_initial = value("ELO_INITIAL"), grid_k = value("ELO_GRID_K"), grid_home = value("ELO_GRID_HOME"),
    bt_iterations = value("BT_ITERATIONS"), od_iterations = value("OD_ITERATIONS"), link_iterations = value("LINK_ITERATIONS"),
    holdout = value("HOLDOUT_ROUND"), upsets = value("UPSETS"), bins = value("CALIBRATION_BINS"), simulations = value("SIMULATIONS"),
    seed = value("SIM_SEED"), top = value("TOP_POSITIONS"), bottom = value("BOTTOM_POSITIONS"))
  list(teams = teams, matches = matches, settings = settings)
}
