source("day_rules.R")
source("tz_parser.R")
source("transitions.R")
source("resolver.R")
source("report.R")

read_lines <- function(name) readLines(file.path("input", name), warn = FALSE)
year_start <- function(year) day_number(year, 1, 1) * seconds_per_day
clock_seconds <- function(text) as.numeric(substr(text, 1, 2)) * 3600 + as.numeric(substr(text, 4, 5)) * 60
names_or_none <- function(names, separator) if (length(names)) paste(names, collapse = separator) else "none"
indented <- function(lines) {
  if (length(lines) > 1) lines[-1] <- paste0("  ", lines[-1])
  lines
}
map_get <- function(table, name, default = NULL) {
  if (exists(name, envir = table, inherits = FALSE)) get(name, envir = table, inherits = FALSE) else default
}
merge_intervals <- function(intervals) {
  if (!length(intervals)) return(list())
  low <- vapply(intervals, function(span) span[1], numeric(1))
  high <- vapply(intervals, function(span) span[2], numeric(1))
  merged <- list()
  for (span in intervals[order(low, high, method = "radix")]) {
    last <- length(merged)
    if (last && span[1] <= merged[[last]][2]) {
      merged[[last]][2] <- max(merged[[last]][2], span[2])
    } else {
      merged[[last + 1]] <- span
    }
  }
  merged
}
intersect_intervals <- function(first, second) {
  pieces <- list()
  for (a in first) for (b in second) {
    low <- max(a[1], b[1])
    high <- min(a[2], b[2])
    if (low < high) pieces[[length(pieces) + 1]] <- c(low, high)
  }
  merge_intervals(pieces)
}
new_source_line <- function(number, content) {
  line <- new.env(parent = emptyenv())
  line$number <- as.numeric(number)
  line$fields <- split_fields(content)
  line$kind <- if (is_continuation(content)) "continuation" else if (line$fields[1] %in% c("Rule", "Zone", "Link")) line$fields[1] else "unknown"
  line$block <- NULL
  line$position <- 0
  line$zone_line <- NULL
  line$field_error <- FALSE
  line$error <- NULL
  line
}
accepts_continuation <- function(line) {
  line$kind == "Zone" && length(line$fields) >= 6 || line$kind == "continuation" && length(line$fields) >= 4
}
add_block_line <- function(block, line) {
  line$block <- block
  line$position <- length(block$lines) + 1
  block$lines[[line$position]] <- line
}
new_block <- function(first) {
  block <- new.env(parent = emptyenv())
  block$name <- first$fields[2]
  block$number <- first$number
  block$lines <- list()
  block$defined <- FALSE
  add_block_line(block, first)
  block
}
new_zone_line <- function(fields) {
  line <- new.env(parent = emptyenv())
  line$stdoff <- parse_offset(fields[1])
  line$rules_text <- fields[2]
  line$rule_set <- NULL
  line$save <- 0
  if (grepl("^[0-9]", line$rules_text)) {
    line$save <- parse_save(line$rules_text)
  } else if (line$rules_text != "-") {
    line$rule_set <- line$rules_text
  }
  line$format_text <- fields[3]
  check_format(line$format_text, !is.null(line$rule_set))
  line$until <- if (length(fields) > 3) parse_until(fields[-seq_len(3)]) else NULL
  line$start <- neg_infinity
  line$end <- pos_infinity
  line
}
rules_notation <- function(line) {
  if (!is.null(line$rule_set)) line$rule_set else if (line$rules_text == "-") "-" else clock_text(line$save)
}
until_notation <- function(line) {
  until <- line$until
  paste(until$year_text, until$month_text, until$day_text, paste0(clock_text(until$time), until$type))
}
new_zone <- function(name, lines) {
  zone <- new.env(parent = emptyenv())
  zone$name <- name
  zone$lines <- lines
  zone$aliases <- character()
  zone$applied <- new.env(hash = TRUE, parent = emptyenv())
  zone$timeline <- NULL
  zone
}
rule_sets <- function(zone) {
  names <- character()
  for (line in zone$lines) if (!is.null(line$rule_set) && !line$rule_set %in% names) names <- c(names, line$rule_set)
  names
}
line_number_at <- function(zone, time) {
  for (i in seq_along(zone$lines)) if (zone$lines[[i]]$start <= time && time < zone$lines[[i]]$end) return(i)
  0L
}
parse_rule <- function(line) {
  fields <- line$fields
  from <- parse_year(fields[3])
  to <- parse_to(fields[4], from)
  if (fields[5] != "-") field_error("syntax error")
  month <- parse_month(fields[6])
  day <- parse_day_spec(fields[7], month)
  at <- parse_time(fields[8])
  save <- parse_save(fields[9])
  letter <- parse_letter(fields[10])
  list(number = line$number, fields = fields, name = fields[2], from = from, to = to, month = month,
       day = day, at = at$value, at_type = at$type, save = save, letter = letter)
}
standard_letter <- function(instances) {
  for (instance in instances) if (instance$rule$save == 0) return(instance$rule$letter)
  ""
}
parse_fields <- function(database, line) {
  if (line$kind == "unknown" || line$kind == "continuation" && is.null(line$block)) field_error("syntax error")
  limits <- list(Rule = c(10, 10), Zone = c(5, 9), continuation = c(3, 7), Link = c(3, 3))[[line$kind]]
  if (length(line$fields) < limits[1] || length(line$fields) > limits[2]) field_error("syntax error")
  if (line$kind == "Rule") {
    rule <- parse_rule(line)
    rules <- map_get(database$rules, rule$name, list())
    if (!length(rules)) database$rule_order <- c(database$rule_order, rule$name)
    rules[[length(rules) + 1]] <- rule
    assign(rule$name, rules, envir = database$rules)
  } else if (line$kind == "Zone") {
    line$zone_line <- new_zone_line(line$fields[-c(1, 2)])
  } else if (line$kind == "continuation") {
    line$zone_line <- new_zone_line(line$fields)
  }
  invisible(NULL)
}
structural_error <- function(database, line, names) {
  current <- line$zone_line
  if (line$kind == "Zone") {
    name <- line$fields[2]
    if (exists(name, envir = names, inherits = FALSE)) return(paste("duplicate zone", name))
    assign(name, TRUE, envir = names)
  }
  if (!is.null(current$rule_set) && !exists(current$rule_set, envir = database$rules, inherits = FALSE)) return(paste("unknown rule", current$rule_set))
  if (is.null(current$until)) return(NULL)
  if (line$kind == "continuation") {
    previous <- line$block$lines[[line$position - 1]]
    if (!previous$field_error && current$until$value <= previous$zone_line$until$value) return("until not increasing")
  }
  if (line$position == length(line$block$lines)) return("missing continuation")
  NULL
}
define_zone <- function(database, block) {
  zone <- new_zone(block$name, lapply(block$lines, function(line) line$zone_line))
  periods <- list()
  add <- function(time, save, letter, line) {
    period <- new_period(time, line$stdoff + save, save != 0, abbreviation(line$format_text, save, letter))
    if (!length(periods) || !same_state(periods[[length(periods)]], period)) periods[[length(periods) + 1]] <<- period
  }
  start <- neg_infinity
  for (line in zone$lines) {
    line$start <- start
    if (is.null(line$rule_set)) {
      if (!is.null(line$until)) line$end <- line$until$value - adjustment(line$until$type, line$stdoff, line$save)
      add(start, line$save, "", line)
    } else {
      instances <- get(line$rule_set, envir = database$sequences, inherits = FALSE)
      run <- run_instances(instances, line$stdoff, start, line$until)
      line$end <- run$end
      save <- 0
      letter <- standard_letter(instances)
      if (length(run$pre_start)) {
        last <- run$pre_start[[length(run$pre_start)]]
        save <- last$save
        letter <- last$letter
      }
      add(start, save, letter, line)
      for (applied in run$applied) {
        rule <- applied$rule
        add(applied$time, rule$save, rule$letter, line)
        key <- integer_text(rule$number)
        assign(key, map_get(zone$applied, key, 0) + 1, envir = zone$applied)
      }
    }
    start <- line$end
  }
  zone$timeline <- new_timeline(periods)
  assign(zone$name, zone, envir = database$zones)
  database$zone_order[[length(database$zone_order) + 1]] <- zone
}
register_link <- function(database, line) {
  target <- line$fields[2]
  alias <- line$fields[3]
  zone <- map_get(database$zones, target)
  if (is.null(zone)) {
    line$error <- paste("unknown link target", target)
  } else if (exists(alias, envir = database$zones, inherits = FALSE) || exists(alias, envir = database$aliases, inherits = FALSE)) {
    line$error <- paste("duplicate link", alias)
  } else {
    assign(alias, zone, envir = database$aliases)
    zone$aliases <- c(zone$aliases, alias)
  }
}
new_database <- function(raw_lines) {
  database <- new.env(parent = emptyenv())
  database$lines <- list()
  database$blocks <- list()
  database$rules <- new.env(hash = TRUE, parent = emptyenv())
  database$rule_order <- character()
  database$sequences <- new.env(hash = TRUE, parent = emptyenv())
  database$zones <- new.env(hash = TRUE, parent = emptyenv())
  database$zone_order <- list()
  database$aliases <- new.env(hash = TRUE, parent = emptyenv())
  for (number in seq_along(raw_lines)) {
    content <- line_content(raw_lines[number])
    if (nchar(content)) database$lines[[length(database$lines) + 1]] <- new_source_line(number, content)
  }
  previous <- NULL
  for (line in database$lines) {
    if (line$kind == "Zone") {
      database$blocks[[length(database$blocks) + 1]] <- new_block(line)
    } else if (line$kind == "continuation" && !is.null(previous) && !is.null(previous$block) && accepts_continuation(previous)) {
      add_block_line(previous$block, line)
    }
    previous <- line
  }
  for (line in database$lines) {
    tryCatch(parse_fields(database, line), field_error = function(problem) {
      line$field_error <- TRUE
      line$error <- conditionMessage(problem)
    })
  }
  zone_names <- new.env(hash = TRUE, parent = emptyenv())
  for (line in database$lines) if (!is.null(line$zone_line)) line$error <- structural_error(database, line, zone_names)
  for (name in database$rule_order) assign(name, instance_sequence(get(name, envir = database$rules, inherits = FALSE)), envir = database$sequences)
  for (block in database$blocks) {
    block$defined <- all(vapply(block$lines, function(line) is.null(line$error), logical(1)))
    if (block$defined) define_zone(database, block)
  }
  for (line in database$lines) if (line$kind == "Link" && is.null(line$error)) register_link(database, line)
  database
}
find_zone <- function(database, word) {
  zone <- map_get(database$zones, word)
  if (is.null(zone)) map_get(database$aliases, word) else zone
}
error_lines <- function(database) {
  lines <- character()
  for (line in database$lines) if (!is.null(line$error)) lines <- c(lines, paste0("line ", integer_text(line$number), ": ", line$error))
  lines
}

offset_shift <- function(timeline, index) timeline$periods[[index]]$offset - timeline$periods[[index - 1]]$offset
transitions_between <- function(timeline, low, high) {
  indices <- seq_along(timeline$periods)
  indices[indices > 1 & low <= timeline$starts & timeline$starts < high]
}
change_at <- function(timeline, index) change_text(timeline$starts[index], timeline$periods[[index - 1]], timeline$periods[[index]])
transition_line <- function(timeline, index) {
  time <- timeline$starts[index]
  shift <- offset_shift(timeline, index)
  kind <- if (shift > 0) paste("gap", duration_text(shift)) else if (shift < 0) paste("overlap", duration_text(-shift)) else "no shift"
  before <- local_text(time + timeline$periods[[index - 1]]$offset)
  after <- local_text(time + timeline$periods[[index]]$offset)
  paste0(change_at(timeline, index), " (local ", before, " -> ", after, ", ", kind, ")")
}
shifts_text <- function(timeline, indices) {
  gaps <- overlaps <- unchanged <- 0
  for (index in indices) {
    shift <- offset_shift(timeline, index)
    if (shift > 0) gaps <- gaps + 1 else if (shift < 0) overlaps <- overlaps + 1 else unchanged <- unchanged + 1
  }
  paste0("gaps ", gaps, ", overlaps ", overlaps, ", no shift ", unchanged)
}
candidate_text <- function(timeline, local, index) {
  period <- timeline$periods[[index]]
  paste0(ut_text(local - period$offset), " (", state_text(period), ")")
}
chosen_candidate <- function(candidates, option) {
  if (length(candidates) == 1 || length(candidates) == 2 && identical(option, "EARLIER")) return(candidates[1])
  if (length(candidates) == 2 && identical(option, "LATER")) return(candidates[2])
  0L
}
unresolved_text <- function(timeline, local, candidates) {
  if (length(candidates)) return(paste("AMBIGUOUS", paste(vapply(candidates, function(index) candidate_text(timeline, local, index), character(1)), collapse = " or ")))
  index <- skipping_transition(timeline, local)
  time <- timeline$starts[index]
  before <- local_text(time + timeline$periods[[index - 1]]$offset)
  after <- local_text(time + timeline$periods[[index]]$offset)
  paste("NONEXISTENT gap", before, "to", after, "at", ut_text(time))
}
working_hours <- function(timeline, start, end) {
  pieces <- list()
  for (index in nearby(timeline, start, end)) {
    offset <- timeline$periods[[index]]$offset
    low <- max(start - offset, timeline$starts[index])
    high <- min(end - offset, end_of(timeline, index))
    if (low < high) pieces[[length(pieces) + 1]] <- c(low, high)
  }
  merge_intervals(pieces)
}
parse_value <- function(kind, word) {
  year <- as.numeric(substr(word, 1, 4))
  if (year < 1800 || year > 2099) return(NULL)
  if (kind == "year") return(year)
  month <- as.numeric(substr(word, 6, 7))
  day <- as.numeric(substr(word, 9, 10))
  if (month < 1 || month > 12 || day < 1 || day > days_in_month(year, month)) return(NULL)
  if (kind == "date") return(day_number(year, month, day))
  hour <- as.numeric(substr(word, 12, 13))
  minute <- as.numeric(substr(word, 15, 16))
  second <- as.numeric(substr(word, 18, 19))
  if (hour > 23 || minute > 59 || second > 59) return(NULL)
  time_value(year, month, day, hour, minute, second)
}
new_query_runner <- function(database, work_start, work_end) {
  runner <- new.env(parent = emptyenv())
  runner$database <- database
  runner$work_start <- work_start
  runner$work_end <- work_end
  runner$answers <- character()
  runner$transition_blocks <- list()
  runner
}
run_query <- function(runner, line) {
  words <- strsplit(line, " ", fixed = TRUE)[[1]]
  command <- words[1]
  arguments <- words[-1]
  option <- NULL
  if (command %in% c("TOUTC", "CONVERT") && tail(arguments, 1) %in% c("EARLIER", "LATER")) {
    option <- tail(arguments, 1)
    arguments <- head(arguments, -1)
  }
  kinds <- if (command == "MEETING") c("date", rep("zone", length(arguments) - 1)) else list(
    TOUTC = c("zone", "local"), TOLOCAL = c("zone", "ut"), CONVERT = c("zone", "zone", "local"),
    OFFSET = c("zone", "ut"), TRANSITIONS = c("zone", "year", "year"), DURATION = c("zone", "local", "local")
  )[[command]]
  values <- list()
  result <- NULL
  for (i in seq_along(arguments)) {
    word <- arguments[i]
    if (kinds[i] == "zone") {
      zone <- find_zone(runner$database, word)
      if (is.null(zone)) {
        result <- paste("ERROR unknown zone", word)
        break
      }
      values[[i]] <- list(zone = zone)
    } else {
      value <- parse_value(kinds[i], word)
      if (is.null(value)) {
        result <- paste("ERROR invalid value", word)
        break
      }
      values[[i]] <- list(value = value)
    }
  }
  if (is.null(result)) result <- query_answer(runner, line, command, values, arguments, option)
  runner$answers <- c(runner$answers, paste(line, "=>", result))
}
query_answer <- function(runner, line, command, values, arguments, option) {
  if (command == "MEETING") return(meeting(runner, values[[1]]$value, lapply(values[-1], function(value) value$zone), arguments[-1]))
  zone <- values[[1]]$zone
  timeline <- zone$timeline
  if (command == "CONVERT") {
    local <- values[[3]]$value
    candidates <- local_candidates(timeline, local)
    index <- chosen_candidate(candidates, option)
    if (!index) return(unresolved_text(timeline, local, candidates))
    time <- local - timeline$periods[[index]]$offset
    period <- period_at(values[[2]]$zone$timeline, time)
    target_local <- time + period$offset
    shift <- floor_div(target_local, seconds_per_day) - floor_div(local, seconds_per_day)
    shift_text <- paste0(if (shift > 0) "+" else "", integer_text(shift))
    return(paste0(local_text(target_local), " (", state_text(period), ") at ", ut_text(time), ", day shift ", shift_text))
  }
  value <- values[[2]]$value
  if (command == "TOUTC") {
    candidates <- local_candidates(timeline, value)
    index <- chosen_candidate(candidates, option)
    return(if (index) candidate_text(timeline, value, index) else unresolved_text(timeline, value, candidates))
  }
  if (command == "TOLOCAL") {
    period <- period_at(timeline, value)
    return(paste0(local_text(value + period$offset), " (", state_text(period), ")"))
  }
  if (command == "OFFSET") {
    index <- index_at(timeline, value)
    text <- state_text(timeline$periods[[index]])
    if (index > 1) text <- paste(text, "since", ut_text(timeline$starts[index]))
    if (index < length(timeline$periods)) text <- paste(text, "until", ut_text(timeline$starts[index + 1]))
    return(text)
  }
  if (command == "TRANSITIONS") {
    last <- values[[3]]$value
    if (value > last) return("ERROR invalid range")
    selected <- transitions_between(timeline, year_start(value), year_start(last + 1))
    block <- c(line, vapply(selected, function(index) transition_line(timeline, index), character(1)), shifts_text(timeline, selected))
    runner$transition_blocks[[length(runner$transition_blocks) + 1]] <- block
    return(paste("transitions:", length(selected)))
  }
  offsets <- numeric(2)
  for (i in seq_len(2)) {
    candidates <- local_candidates(timeline, values[[i + 1]]$value)
    if (length(candidates) == 2) return(paste("AMBIGUOUS", arguments[i + 1]))
    if (!length(candidates)) return(paste("NONEXISTENT", arguments[i + 1]))
    offsets[i] <- timeline$periods[[candidates[1]]]$offset
  }
  second <- values[[3]]$value
  elapsed <- (second - offsets[2]) - (value - offsets[1])
  paste0(integer_text(elapsed), " s (", duration_text(elapsed), "), wall clock ", duration_text(second - value), ", offset change ", offset_text(offsets[2] - offsets[1]))
}
meeting <- function(runner, day, zones, words) {
  start <- day * seconds_per_day + runner$work_start
  end <- day * seconds_per_day + runner$work_end
  common <- working_hours(zones[[1]]$timeline, start, end)
  if (length(zones) > 1) for (zone in zones[-1]) common <- intersect_intervals(common, working_hours(zone$timeline, start, end))
  if (!length(common)) return("NONE")
  parts <- character()
  for (span in common) {
    low <- span[1]
    high <- span[2]
    members <- character()
    for (i in seq_along(zones)) {
      period <- period_at(zones[[i]]$timeline, low)
      members <- c(members, paste(words[i], local_text(low + period$offset), period$abbreviation))
    }
    parts <- c(parts, paste0(ut_text(low), " to ", ut_text(high), " (", duration_text(high - low), ") [", paste(members, collapse = ", "), "]"))
  }
  paste(parts, collapse = "; ")
}

rule_text <- function(rule) {
  fields <- rule$fields
  paste("rule", rule$name, fields[3], fields[4], fields[6], fields[7], paste0(clock_text(rule$at), rule$at_type), clock_text(rule$save), fields[10])
}
database_block <- function(database) {
  rule_lines <- Filter(function(line) line$kind == "Rule", database$lines)
  link_lines <- Filter(function(line) line$kind == "Link", database$lines)
  valid_rules <- sum(vapply(rule_lines, function(line) is.null(line$error), logical(1)))
  valid_links <- sum(vapply(link_lines, function(line) is.null(line$error), logical(1)))
  used <- character()
  zone_lines <- 0
  for (zone in database$zone_order) {
    used <- union(used, rule_sets(zone))
    zone_lines <- zone_lines + length(zone$lines)
  }
  unused <- database$rule_order[!database$rule_order %in% used]
  invalid <- character()
  for (block in database$blocks) if (!block$defined) invalid <- c(invalid, paste0(block$name, " (line ", integer_text(block$number), ")"))
  lines <- c("DATABASE", paste0("rule lines: ", valid_rules, " valid, ", length(rule_lines) - valid_rules, " invalid"),
             paste0("zones: ", length(database$zone_order), " defined, ", length(database$blocks) - length(database$zone_order), " invalid"),
             paste0("zone lines: ", zone_lines, " in defined zones"), paste0("links: ", valid_links, " defined, ", length(link_lines) - valid_links, " invalid"),
             paste0("errors: ", length(error_lines(database))), paste0("unused rules: ", names_or_none(unused, " ")), paste0("invalid zones: ", names_or_none(invalid, ", ")))
  for (name in database$rule_order) {
    rules <- get(name, envir = database$rules, inherits = FALSE)
    first <- min(vapply(rules, function(rule) rule$from, numeric(1)))
    last <- if (any(vapply(rules, function(rule) rule$fields[4] == "max", logical(1)))) "max" else integer_text(max(vapply(rules, function(rule) rule$to, numeric(1))))
    count <- sum(vapply(database$zone_order, function(zone) name %in% rule_sets(zone), logical(1)))
    lines <- c(lines, paste0("rule set ", name, ": lines ", length(rules), ", years ", integer_text(first), "-", last, ", zones ", count))
  }
  lines
}
dst_lines <- function(timeline, reference) {
  indices <- which(vapply(timeline$periods, function(period) period$dst, logical(1)))
  if (length(indices)) {
    years <- vapply(indices, function(index) split_time(timeline$starts[index])[1], numeric(1))
    lines <- paste0("dst years: ", min(years), "-", max(years))
  } else {
    lines <- "dst years: none"
  }
  year <- split_time(reference)[1]
  low <- year_start(year)
  high <- year_start(year + 1)
  pieces <- list()
  for (index in indices) {
    start <- max(low, timeline$starts[index])
    end <- min(high, end_of(timeline, index))
    if (start < end) pieces[[length(pieces) + 1]] <- c(start, end)
  }
  total <- 0
  for (span in merge_intervals(pieces)) {
    lines <- c(lines, paste0("dst period: ", ut_text(span[1]), " to ", ut_text(span[2]), " (", duration_text(span[2] - span[1]), ")"))
    total <- total + span[2] - span[1]
  }
  c(lines, paste0("dst total ", integer_text(year), ": ", duration_text(total)))
}
zone_block <- function(database, zone, reference) {
  timeline <- zone$timeline
  periods <- timeline$periods
  lines <- c(paste("ZONE", zone$name), paste0("aliases: ", names_or_none(zone$aliases, " ")))
  for (i in seq_along(zone$lines)) {
    line <- zone$lines[[i]]
    text <- paste0("line ", i, ": ", offset_text(line$stdoff), " ", rules_notation(line), " ", line$format_text)
    if (i > 1) text <- paste(text, "from", ut_text(line$start))
    if (!is.null(line$until)) text <- paste(text, "until", until_notation(line), "=", ut_text(line$end))
    lines <- c(lines, paste0(text, ", transitions ", length(transitions_between(timeline, line$start, line$end))))
  }
  for (name in rule_sets(zone)) for (rule in get(name, envir = database$rules, inherits = FALSE)) {
    applied <- map_get(zone$applied, integer_text(rule$number), 0)
    lines <- c(lines, paste0(rule_text(rule), ", applied ", applied))
  }
  offsets <- vapply(periods, function(period) period$offset, numeric(1))
  lines <- c(lines, paste("offset range:", offset_text(min(offsets)), "to", offset_text(max(offsets))))
  states <- vapply(periods, state_text, character(1))
  for (state in unique(states)) lines <- c(lines, paste0("state ", state, ", periods ", sum(states == state)))
  index <- index_at(timeline, reference)
  period <- periods[[index]]
  lines <- c(lines, paste0("reference: ", local_text(reference + period$offset), " (", state_text(period), "), line ", line_number_at(zone, reference)))
  previous <- if (index > 1) change_at(timeline, index) else "none"
  next_change <- if (index < length(periods)) change_at(timeline, index + 1) else "none"
  every <- seq_along(periods)[-1]
  lines <- c(lines, paste("previous transition:", previous), paste("next transition:", next_change), paste0("transitions: ", length(every), ", ", shifts_text(timeline, every)))
  c(lines, dst_lines(timeline, reference))
}
main <- function() {
  database <- new_database(read_lines("tzdata.txt"))
  params <- read_lines("params.txt")
  reference <- parse_value("ut", strsplit(params[1], " ", fixed = TRUE)[[1]][2])
  workday <- strsplit(params[2], " ", fixed = TRUE)[[1]]
  runner <- new_query_runner(database, clock_seconds(workday[2]), clock_seconds(workday[3]))
  for (line in read_lines("queries.txt")) run_query(runner, line)
  blocks <- list(indented(database_block(database)))
  for (name in sort(ls(database$zones, all.names = TRUE), method = "radix")) blocks[[length(blocks) + 1]] <- indented(zone_block(database, get(name, envir = database$zones, inherits = FALSE), reference))
  dir.create("output", showWarnings = FALSE, recursive = TRUE)
  write_lines("answers.txt", runner$answers)
  write_lines("errors.txt", error_lines(database))
  write_blocks("transitions.txt", runner$transition_blocks)
  write_blocks("zone_summary.txt", blocks)
}
main()
