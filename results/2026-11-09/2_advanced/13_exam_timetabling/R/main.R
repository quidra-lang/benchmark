script_args <- grep("^--file=", commandArgs(), value = TRUE)
source_dir <- if (length(script_args)) dirname(sub("^--file=", "", script_args[1L])) else "R"
for (unit in c("enrolment", "conflict_graph", "coloring", "rooms", "report")) source(file.path(source_dir, paste0(unit, ".R")))

RELATIONS <- c("back_to_back", "same_day", "overnight")
EXCHANGE_VERDICTS <- c("fixed", "invalid", "worse", "applied")
SWAP_VERDICTS <- c("fixed", "invalid", "rooms", "worse", "applied")
read_lines <- function(name) readLines(file.path("input", name), warn = FALSE)
ceil_div <- function(a, b) (a + b - 1L) %/% b
verdict_counts <- function(tally, verdicts) paste(paste(verdicts, tally[verdicts]), collapse = " ")

new_calendar <- function(lines) {
  settings <- lapply(lines[seq_len(6L)], function(line) as.integer(strsplit(line, " ", fixed = TRUE)[[1L]][-1L]))
  list2env(list(days = settings[[1L]][1L], lengths = settings[[2L]], periods = length(settings[[2L]]),
    limit = settings[[3L]][1L], weights = settings[[4L]], front_count = settings[[5L]][1L],
    deadline = settings[[5L]][2L], ratio = settings[[6L]][1L], slot_count = settings[[1L]][1L] * length(settings[[2L]]),
    closed = integer(), unavailable = list(), fixed = setNames(integer(), character()), orders = list(), arrows = list()), parent = emptyenv())
}
slots <- function(calendar) seq_len(calendar$slot_count)
day_of <- function(calendar, slot) (slot - 1L) %/% calendar$periods + 1L
slot_name <- function(calendar, slot) paste0("D", day_of(calendar, slot), "P", (slot - 1L) %% calendar$periods + 1L)
slot_length <- function(calendar, slot) calendar$lengths[(slot - 1L) %% calendar$periods + 1L]
slot_at <- function(calendar, day_text, period_text) {
  day <- as.integer(day_text)
  period <- as.integer(period_text)
  if (day >= 1L && day <= calendar$days && period >= 1L && period <= calendar$periods) (day - 1L) * calendar$periods + period else 0L
}
relation <- function(calendar, first, second) {
  low <- min(first, second)
  high <- max(first, second)
  if (day_of(calendar, low) == day_of(calendar, high)) {
    if (high - low == 1L) return(1L)
    if (high - low >= 2L) return(2L)
  } else if (high - low == 1L) return(3L)
  0L
}
breakdown_text <- function(value) sprintf("back_to_back %d same_day %d overnight %d front_load %d penalty %d", value$counts[1L], value$counts[2L], value$counts[3L], value$late, value$total)

new_scheduler <- function(state, calendar) {
  state$calendar <- calendar
  state$largest_room <- max(vapply(state$rooms, `[[`, 0L, "capacity"))
  ids <- ascii_sort(names(state$courses))
  sizes <- vapply(state$courses[ids], enrolment_count, 0L)
  state$empty <- ids[sizes == 0L]
  state$oversized <- ids[sizes > state$largest_room]
  state$schedulable <- setdiff(ids, c(state$empty, state$oversized))
  state$graph <- conflict_graph(ids[sizes > 0L], state$students)
  state$edges <- graph_edges(state$graph)
  state$front_load <- head(by_size(state, state$schedulable), calendar$front_count)
  state$open_slots <- state$fixed_slots <- integer()
  state$assignment <- setNames(integer(), character())
  state$penalty <- 0L
  state$attempts <- state$assignment_order <- state$insertions <- list()
  state$excluded <- character()
  state$reasons <- list()
  state$initial <- state$exchanged <- NULL
  state$exchange_log <- state$swap_log <- character()
  state$placements <- state$slot_placements <- list()
  state
}
by_size <- function(s, ids) ids[order(-vapply(s$courses[ids], enrolment_count, 0L), ids, method = "radix")]
by_degree <- function(s, ids) ids[order(-vapply(ids, function(id) degree(s$graph, id), 0L), ids, method = "radix")]
blocked_students <- function(s, course, slot) course$students[vapply(course$students, function(student) slot %in% s$calendar$unavailable[[student]], FALSE)]
suitable <- function(s, course, slot) slot_length(s$calendar, slot) >= course$duration && !length(blocked_students(s, course, slot))
packs <- function(s, ids) !is.null(pack(s$rooms, unname(s$courses[ids])))
outside <- function(day, period) paste("slot", day, period, "outside calendar")
courses_at <- function(assignment, slot) ascii_sort(names(assignment)[assignment == slot])

accept_closed <- function(s, fields) {
  slot <- slot_at(s$calendar, fields[1L], fields[2L])
  if (!slot) return(outside(fields[1L], fields[2L]))
  if (slot %in% s$calendar$closed) return(paste("duplicate closed", slot_name(s$calendar, slot)))
  s$calendar$closed <- c(s$calendar$closed, slot)
  NULL
}
accept_unavailable <- function(s, fields) {
  student <- fields[1L]
  if (!student %in% names(s$students)) return(paste("unknown student", student))
  slot <- slot_at(s$calendar, fields[2L], fields[3L])
  if (!slot) return(outside(fields[2L], fields[3L]))
  if (slot %in% s$calendar$unavailable[[student]]) return(paste("duplicate unavailable", student, slot_name(s$calendar, slot)))
  s$calendar$unavailable[[student]] <- c(s$calendar$unavailable[[student]], slot)
  NULL
}
accept_fixed <- function(s, fields) {
  id <- fields[1L]
  if (!id %in% names(s$courses)) return(paste("unknown course", id))
  if (!id %in% s$schedulable) return(paste("course", id, "not schedulable"))
  slot <- slot_at(s$calendar, fields[2L], fields[3L])
  if (!slot) return(outside(fields[2L], fields[3L]))
  name <- slot_name(s$calendar, slot)
  if (slot %in% s$calendar$closed) return(paste("slot", name, "closed"))
  if (!suitable(s, s$courses[[id]], slot)) return(paste("slot", name, "unsuitable for", id))
  if (id %in% names(s$calendar$fixed)) return(paste("duplicate fixed", id))
  group <- courses_at(s$calendar$fixed, slot)
  clashes <- intersect(group, names(neighbours(s$graph, id)))
  if (length(clashes)) return(paste("conflict", id, ascii_sort(clashes)[1L]))
  if (!packs(s, c(group, id))) return(paste("rooms full", name))
  s$calendar$fixed[[id]] <- slot
  NULL
}
accept_after <- function(s, fields) {
  later <- fields[1L]
  earlier <- fields[2L]
  for (id in fields) if (!id %in% names(s$courses)) return(paste("unknown course", id))
  for (id in fields) if (!id %in% s$schedulable) return(paste("course", id, "not schedulable"))
  if (later == earlier) return(paste("bad order", later, earlier))
  if (any(vapply(s$calendar$orders, function(pair) identical(pair, fields), FALSE))) return(paste("duplicate order", later, earlier))
  if (reachable(s$calendar$arrows, earlier, later)) return(paste("cycle", later, earlier))
  fixed <- s$calendar$fixed
  if (all(fields %in% names(fixed)) && fixed[[later]] <= fixed[[earlier]]) return(paste("fixed order", later, earlier))
  s$calendar$orders[[length(s$calendar$orders) + 1L]] <- fields
  s$calendar$arrows[[later]] <- c(s$calendar$arrows[[later]], earlier)
  NULL
}
validate_calendar <- function(s, lines) {
  handlers <- list(closed = accept_closed, unavailable = accept_unavailable, fixed = accept_fixed, after = accept_after)
  if (length(lines) > 6L) for (number in seq.int(7L, length(lines))) {
    fields <- strsplit(lines[number], " ", fixed = TRUE)[[1L]]
    message <- handlers[[fields[1L]]](s, fields[-1L])
    if (!is.null(message)) s$errors <- c(s$errors, sprintf("calendar.txt line %d: %s", number, message))
  }
  s$open_slots <- setdiff(slots(s$calendar), s$calendar$closed)
  s$fixed_slots <- unique(unname(s$calendar$fixed))
}

order_conflicts <- function(s, id, slot, assignment) {
  conflicts <- character()
  for (pair in s$calendar$orders) {
    later <- pair[1L]
    earlier <- pair[2L]
    if (later == id && earlier %in% names(assignment) && slot <= assignment[[earlier]]) {
      conflicts <- c(conflicts, earlier)
    } else if (earlier == id && later %in% names(assignment) && slot >= assignment[[later]]) {
      conflicts <- c(conflicts, later)
    }
  }
  conflicts
}
orders_satisfied <- function(s, assignment) {
  all(vapply(s$calendar$orders, function(pair) !all(pair %in% names(assignment)) || assignment[[pair[1L]]] > assignment[[pair[2L]]], FALSE))
}
candidate_slots <- function(s, id, assignment) {
  candidates <- integer()
  for (slot in s$open_slots) {
    if (!suitable(s, s$courses[[id]], slot)) next
    adjacent <- intersect(names(neighbours(s$graph, id)), names(assignment))
    if (any(assignment[adjacent] == slot)) next
    if (length(order_conflicts(s, id, slot, assignment))) next
    if (packs(s, c(courses_at(assignment, slot), id))) candidates <- c(candidates, slot)
  }
  candidates
}
build_timetable <- function(s) {
  repeat {
    pending <- setdiff(s$schedulable, c(names(s$calendar$fixed), s$excluded))
    work <- list2env(list(assignment = s$calendar$fixed), parent = emptyenv())
    attempt <- new_attempt(pending, s$graph, s$calendar$limit, function(id, assignment) candidate_slots(s, id, assignment))
    succeeded <- attempt_search(attempt, work)
    failed <- if (succeeded) NULL else attempt$dead_end_course
    s$attempts[[length(s$attempts) + 1L]] <- list(length(pending), attempt$dead_ends, failed)
    if (succeeded) {
      s$assignment <- work$assignment
      s$assignment_order <- lapply(attempt$chosen, function(chosen) list(chosen[[1L]], work$assignment[[chosen[[1L]]]], chosen[[2L]]))
      return(invisible(NULL))
    }
    s$excluded <- c(s$excluded, failed)
  }
}

penalty_pairs <- function(s, assignment) {
  result <- list()
  for (edge in s$edges) {
    first <- edge[[1L]]
    second <- edge[[2L]]
    if (all(c(first, second) %in% names(assignment))) {
      kind <- relation(s$calendar, assignment[[first]], assignment[[second]])
      if (kind) result[[length(result) + 1L]] <- list(first, second, kind, edge[[3L]])
    }
  }
  result
}
late_courses <- function(s, assignment) s$front_load[s$front_load %in% names(assignment) & assignment[s$front_load] > s$calendar$deadline]
breakdown <- function(s, assignment) {
  counts <- integer(3L)
  for (pair in penalty_pairs(s, assignment)) counts[pair[[3L]]] <- counts[pair[[3L]]] + pair[[4L]]
  late <- length(late_courses(s, assignment))
  list(counts = counts, late = late, total = sum(s$calendar$weights[1:3] * counts) + s$calendar$weights[4L] * late)
}
contributions <- function(s) {
  result <- setNames(integer(length(s$assignment)), names(s$assignment))
  for (pair in penalty_pairs(s, s$assignment)) {
    value <- s$calendar$weights[pair[[3L]]] * pair[[4L]]
    result[pair[[1L]]] <- result[pair[[1L]]] + value
    result[pair[[2L]]] <- result[pair[[2L]]] + value
  }
  for (id in late_courses(s, s$assignment)) result[id] <- result[id] + s$calendar$weights[4L]
  result
}
blocking_reason <- function(s, id, slot) {
  course <- s$courses[[id]]
  if (slot %in% s$calendar$closed) return("closed")
  if (slot_length(s$calendar, slot) < course$duration) return("too_short")
  blocked <- blocked_students(s, course, slot)
  if (length(blocked)) return(paste("unavailable", ascii_sort(blocked)[1L]))
  adjacent <- neighbours(s$graph, id)
  clashes <- intersect(names(adjacent), courses_at(s$assignment, slot))
  if (length(clashes)) {
    other <- clashes[order(-adjacent[clashes], clashes, method = "radix")][1L]
    return(paste("conflict", other, "shared", adjacent[[other]]))
  }
  conflicts <- order_conflicts(s, id, slot, s$assignment)
  if (length(conflicts)) return(paste("order", ascii_sort(conflicts)[1L]))
  "rooms"
}
insert_excluded <- function(s) {
  for (id in ascii_sort(s$excluded)) {
    candidates <- candidate_slots(s, id, s$assignment)
    if (!length(candidates)) {
      s$reasons[[id]] <- vapply(slots(s$calendar), function(slot) blocking_reason(s, id, slot), "")
      next
    }
    before <- breakdown(s, s$assignment)$total
    totals <- vapply(candidates, function(slot) {
      trial <- s$assignment
      trial[[id]] <- slot
      breakdown(s, trial)$total
    }, 0)
    best <- order(totals, candidates)[1L]
    s$assignment[[id]] <- candidates[best]
    s$insertions[[length(s$insertions) + 1L]] <- list(id, candidates[best], totals[best] - before)
  }
  s$initial <- breakdown(s, s$assignment)
  s$penalty <- s$initial$total
}
unscheduled <- function(s) ascii_sort(c(setdiff(s$excluded, names(s$assignment)), s$oversized))
valid_trial <- function(s, trial, moved) all(vapply(moved, function(id) suitable(s, s$courses[[id]], trial[[id]]), FALSE)) && orders_satisfied(s, trial)
moved_courses <- function(s, trial) ascii_sort(names(trial)[trial != s$assignment[names(trial)]])

exchange_trial <- function(s, home, target) {
  if (any(c(home, target) %in% s$fixed_slots)) return(list("fixed", NULL, NULL))
  trial <- s$assignment
  trial[s$assignment == home] <- target
  trial[s$assignment == target] <- home
  if (!valid_trial(s, trial, moved_courses(s, trial))) return(list("invalid", NULL, NULL))
  total <- breakdown(s, trial)$total
  if (total >= s$penalty) return(list("worse", NULL, NULL))
  list("applied", trial, total)
}
exchange_slots <- function(s) {
  round_number <- serial <- 0L
  repeat {
    round_number <- round_number + 1L
    tally <- setNames(integer(length(EXCHANGE_VERDICTS)), EXCHANGE_VERDICTS)
    records <- character()
    pairs <- 0L
    for (home in s$open_slots) for (target in s$open_slots[s$open_slots > home]) {
      pairs <- pairs + 1L
      result <- exchange_trial(s, home, target)
      verdict <- result[[1L]]
      tally[verdict] <- tally[verdict] + 1L
      if (verdict == "applied") {
        serial <- serial + 1L
        records <- c(records, sprintf("EXCHANGE %d %s %s penalty %d -> %d", serial, slot_name(s$calendar, home), slot_name(s$calendar, target), s$penalty, result[[3L]]))
        s$assignment <- result[[2L]]
        s$penalty <- result[[3L]]
      }
    }
    s$exchange_log <- c(s$exchange_log, paste("ROUND", round_number, "pairs", pairs, verdict_counts(tally, EXCHANGE_VERDICTS)), records)
    if (!tally[["applied"]]) break
  }
  s$exchanged <- breakdown(s, s$assignment)
}
swap_trial <- function(s, id, home, target) {
  chain <- kempe_chain(s$graph, s$assignment, id, home, target)
  if (any(chain %in% names(s$calendar$fixed))) return(list("fixed", NULL, NULL))
  trial <- s$assignment
  trial[chain] <- ifelse(s$assignment[chain] == home, target, home)
  if (!valid_trial(s, trial, chain)) return(list("invalid", NULL, NULL))
  if (!packs(s, courses_at(trial, home)) || !packs(s, courses_at(trial, target))) return(list("rooms", NULL, NULL))
  total <- breakdown(s, trial)$total
  if (total >= s$penalty) return(list("worse", NULL, NULL))
  list("applied", trial, total)
}
swap_chains <- function(s) {
  pass_number <- serial <- 0L
  repeat {
    pass_number <- pass_number + 1L
    tally <- setNames(integer(length(SWAP_VERDICTS)), SWAP_VERDICTS)
    records <- character()
    candidates <- 0L
    movable <- ascii_sort(setdiff(names(s$assignment), names(s$calendar$fixed)))
    for (id in movable) {
      home <- s$assignment[[id]]
      for (target in s$open_slots[s$open_slots != home]) {
        candidates <- candidates + 1L
        result <- swap_trial(s, id, home, target)
        verdict <- result[[1L]]
        tally[verdict] <- tally[verdict] + 1L
        if (verdict != "applied") next
        serial <- serial + 1L
        trial <- result[[2L]]
        chain <- moved_courses(s, trial)
        records <- c(records, sprintf("SWAP %d %s %s %s chain %d penalty %d -> %d", serial, id, slot_name(s$calendar, home), slot_name(s$calendar, target), length(chain), s$penalty, result[[3L]]))
        for (member in chain) records <- c(records, paste("  MOVE", member, slot_name(s$calendar, s$assignment[[member]]), "->", slot_name(s$calendar, trial[[member]])))
        s$assignment <- trial
        s$penalty <- result[[3L]]
        break
      }
    }
    s$swap_log <- c(s$swap_log, paste("PASS", pass_number, "candidates", candidates, verdict_counts(tally, SWAP_VERDICTS)), records)
    if (!tally[["applied"]]) break
  }
}

assign_rooms <- function(s) {
  for (slot in s$open_slots) {
    placed <- pack(s$rooms, unname(s$courses[courses_at(s$assignment, slot)]))
    s$slot_placements[[as.character(slot)]] <- placed
    for (placement in placed) s$placements[[placement$course$id]] <- placement
  }
}
room_groups <- function(s, slot) {
  result <- list()
  for (room in s$rooms) {
    placed <- Filter(function(p) p$room$id == room$id, s$slot_placements[[as.character(slot)]])
    if (length(placed)) result[[length(result) + 1L]] <- list(room = room, placed = placed)
  }
  result
}
invigilators <- function(s, slot) sum(vapply(room_groups(s, slot), function(group) ceil_div(sum(vapply(group$placed, function(p) enrolment_count(p$course), 0L)), s$calendar$ratio), 0))
slot_load <- function(s, slot) {
  ids <- courses_at(s$assignment, slot)
  c(length(ids), sum(vapply(s$courses[ids], enrolment_count, 0L)))
}
assigned_courses <- function(s, student) {
  ids <- intersect(s$students[[student]], names(s$assignment))
  ids[order(s$assignment[ids], ids, method = "radix")]
}
assigned_slots <- function(s, student) unname(s$assignment[assigned_courses(s, student)])
student_pairs <- function(s, student) {
  ids <- assigned_courses(s, student)
  result <- list()
  if (length(ids) < 2L) return(result)
  for (i in seq_len(length(ids) - 1L)) for (j in seq.int(i + 1L, length(ids))) {
    low <- s$assignment[[ids[i]]]
    high <- s$assignment[[ids[j]]]
    kind <- relation(s$calendar, low, high)
    if (kind) result[[length(result) + 1L]] <- list(kind, low, ids[i], high, ids[j])
  }
  result
}
student_penalty <- function(s, student) {
  counts <- integer(3L)
  for (pair in student_pairs(s, student)) counts[pair[[1L]]] <- counts[pair[[1L]]] + 1L
  list(counts = counts, penalty = sum(s$calendar$weights[1:3] * counts))
}

timetable_lines <- function(s) {
  cal <- s$calendar
  lines <- sprintf("TIMETABLE days %d periods %d open %d courses %d scheduled %d unscheduled %d empty %d", cal$days, cal$periods, length(s$open_slots), length(s$courses), length(s$assignment), length(unscheduled(s)), length(s$empty))
  lines <- c(lines, fixed_width_line("DAY", c(paste0("P", seq_len(cal$periods)), "TOTAL"), 4L, 10L))
  for (day in seq_len(cal$days)) {
    cells <- character()
    total <- c(0L, 0L)
    for (period in seq_len(cal$periods)) {
      slot <- (day - 1L) * cal$periods + period
      if (slot %in% cal$closed) cells <- c(cells, "closed") else {
        load <- slot_load(s, slot)
        cells <- c(cells, paste(load, collapse = "/"))
        total <- total + load
      }
    }
    lines <- c(lines, fixed_width_line(paste0("D", day), c(cells, paste(total, collapse = "/")), 4L, 10L))
  }
  for (slot in slots(cal)) {
    prefix <- paste("SLOT", slot, slot_name(cal, slot), "minutes", slot_length(cal, slot))
    if (slot %in% cal$closed) {
      lines <- c(lines, paste(prefix, "closed"))
      next
    }
    load <- slot_load(s, slot)
    groups <- room_groups(s, slot)
    seats <- sum(vapply(groups, function(group) group$room$capacity, 0L))
    lines <- c(lines, paste(prefix, "exams", load[1L], "students", load[2L], "rooms", length(groups), "seats", seats, "invigilators", invigilators(s, slot)))
    for (p in s$slot_placements[[as.character(slot)]]) {
      course <- p$course
      marker <- if (course$id %in% names(cal$fixed)) " fixed" else ""
      lines <- c(lines, sprintf("  %s %dmin students %d room %s seats %d-%d%s %s", course$id, course$duration, enrolment_count(course), p$room$id, p$first_seat, p$last_seat, marker, course$name))
    }
  }
  for (room in s$rooms) {
    used <- exams <- seated <- 0L
    for (slot in s$open_slots) for (group in room_groups(s, slot)) if (room$id == group$room$id) {
      used <- used + 1L
      exams <- exams + length(group$placed)
      seated <- seated + sum(vapply(group$placed, function(p) enrolment_count(p$course), 0L))
    }
    utilization <- rounded_percent(seated, room$capacity * length(s$open_slots))
    lines <- c(lines, paste("ROOM", room$id, "capacity", room$capacity, "slots", used, "exams", exams, "seated", seated, "utilization", utilization))
  }
  c(lines, paste("INVIGILATORS total", sum(vapply(s$open_slots, function(slot) invigilators(s, slot), 0)), "ratio", cal$ratio))
}
room_lines <- function(s) {
  lines <- "slot,room,course,students,first_seat,last_seat"
  for (slot in s$open_slots) for (group in room_groups(s, slot)) for (p in group$placed) lines <- c(lines, paste(slot_name(s$calendar, slot), group$room$id, p$course$id, enrolment_count(p$course), p$first_seat, p$last_seat, sep = ","))
  lines
}
student_statistics <- function(s) {
  histogram <- gaps <- dayloads <- numeric()
  ranking <- list()
  add <- function(counts, value) {
    key <- as.character(value)
    counts[key] <- if (key %in% names(counts)) counts[[key]] + 1L else 1L
    counts
  }
  for (student in names(s$students)) {
    value <- student_penalty(s, student)
    histogram <- add(histogram, value$penalty)
    ranking[[student]] <- value
    assigned <- assigned_slots(s, student)
    for (gap in diff(assigned)) gaps <- add(gaps, gap)
    if (length(assigned)) dayloads <- add(dayloads, max(tabulate(day_of(s$calendar, assigned), nbins = s$calendar$days)))
  }
  lines <- character()
  for (kind in c("HISTOGRAM", "GAP", "DAYLOAD")) {
    counts <- switch(kind, HISTOGRAM = histogram, GAP = gaps, DAYLOAD = dayloads)
    for (key in names(counts)[order(as.integer(names(counts)))]) lines <- c(lines, paste(kind, key, counts[[key]]))
  }
  ids <- names(ranking)
  ranked <- ids[order(-vapply(ranking, `[[`, 0, "penalty"), ids, method = "radix")]
  for (student in head(ranked, 5L)) {
    value <- ranking[[student]]
    if (value$penalty > 0L) lines <- c(lines, sprintf("WORST %s penalty %d back_to_back %d same_day %d overnight %d", student, value$penalty, value$counts[1L], value$counts[2L], value$counts[3L]))
  }
  lines
}
penalty_lines <- function(s) {
  cal <- s$calendar
  weights <- cal$weights
  final <- breakdown(s, s$assignment)
  lines <- c(sprintf("WEIGHTS back_to_back %d same_day %d overnight %d front_load %d", weights[1L], weights[2L], weights[3L], weights[4L]),
    paste("FRONT_LOAD courses", length(s$front_load), "last_slot", slot_name(cal, cal$deadline)), paste("INITIAL", breakdown_text(s$initial)),
    s$exchange_log, paste("EXCHANGED", breakdown_text(s$exchanged)), s$swap_log, paste("FINAL", breakdown_text(final)), paste("SAVED", s$initial$total - final$total))
  daily <- matrix(0L, cal$days, 3L)
  for (pair in penalty_pairs(s, s$assignment)) {
    day <- day_of(cal, min(s$assignment[[pair[[1L]]]], s$assignment[[pair[[2L]]]]))
    daily[day, pair[[3L]]] <- daily[day, pair[[3L]]] + pair[[4L]]
  }
  for (day in seq_len(cal$days)) lines <- c(lines, sprintf("DAY D%d back_to_back %d same_day %d overnight %d", day, daily[day, 1L], daily[day, 2L], daily[day, 3L]))
  for (id in late_courses(s, s$assignment)) lines <- c(lines, paste("LATE", id, slot_name(cal, s$assignment[[id]]), "students", enrolment_count(s$courses[[id]])))
  values <- contributions(s)
  ids <- names(values)
  ranked <- ids[order(-values, ids, method = "radix")]
  for (id in head(ranked, 10L)) if (values[[id]] > 0L) lines <- c(lines, paste("COURSE", id, slot_name(cal, s$assignment[[id]]), "penalty", values[[id]]))
  c(lines, student_statistics(s))
}
schedule_lines <- function(s, queries) {
  lines <- character()
  for (student in queries) {
    if (!student %in% names(s$students)) {
      lines <- c(lines, paste("STUDENT", student, "not found"))
      next
    }
    ids <- s$students[[student]]
    assigned <- assigned_courses(s, student)
    lines <- c(lines, paste("STUDENT", student, "exams", length(ids), "scheduled", length(assigned), "penalty", student_penalty(s, student)$penalty))
    for (id in assigned) {
      p <- s$placements[[id]]
      seat <- p$first_seat + match(student, p$course$students) - 1L
      lines <- c(lines, paste(" ", slot_name(s$calendar, s$assignment[[id]]), id, "room", p$room$id, "seat", seat, p$course$name))
    }
    for (id in setdiff(ids, names(s$assignment))) lines <- c(lines, paste("  UNSCHEDULED", id, s$courses[[id]]$name))
    for (pair in student_pairs(s, student)) lines <- c(lines, paste(paste0("  ", toupper(RELATIONS[pair[[1L]]])), slot_name(s$calendar, pair[[2L]]), pair[[3L]], slot_name(s$calendar, pair[[4L]]), pair[[5L]]))
    for (slot in sort(s$calendar$unavailable[[student]])) lines <- c(lines, paste("  UNAVAILABLE", slot_name(s$calendar, slot)))
  }
  lines
}
status_lines <- function(s) {
  values <- contributions(s)
  lines <- "course,status,slot,students,minutes,degree,penalty"
  for (id in ascii_sort(names(s$courses))) {
    course <- s$courses[[id]]
    status <- if (id %in% names(s$calendar$fixed)) "fixed" else if (id %in% names(s$assignment)) "scheduled" else if (id %in% s$oversized) "too_large" else if (id %in% s$empty) "empty" else "no_slot"
    slot <- if (id %in% names(s$assignment)) slot_name(s$calendar, s$assignment[[id]]) else "-"
    contribution <- if (id %in% names(values)) values[[id]] else 0L
    lines <- c(lines, paste(id, status, slot, enrolment_count(course), course$duration, degree(s$graph, id), contribution, sep = ","))
  }
  lines
}
graph_lines <- function(s) {
  vertices <- length(s$graph$vertices)
  edges <- length(s$edges)
  shared <- sum(vapply(s$edges, `[[`, 0L, 3L))
  density <- if (vertices >= 2L) (2000 * edges) %/% (vertices * (vertices - 1L)) else 0L
  lines <- paste("GRAPH courses", vertices, "edges", edges, "shared", shared, "density", density)
  for (id in head(by_degree(s, s$graph$vertices), 5L)) lines <- c(lines, paste("DEGREE", id, "neighbours", degree(s$graph, id), "shared", shared_total(s$graph, id), "students", enrolment_count(s$courses[[id]])))
  groups <- graph_components(s$graph)
  lines <- c(lines, paste("COMPONENTS", length(groups)))
  for (number in seq_along(groups)) lines <- c(lines, paste("COMPONENT", number, "size", length(groups[[number]]), "first", groups[[number]][1L]))
  clique <- greedy_clique(s$graph, s$schedulable)
  c(lines, paste(c("CLIQUE", "size", length(clique), clique), collapse = " "))
}
capacity_lines <- function(s) {
  loads <- lengths(s$students)
  most <- max(loads)
  demand <- sum(vapply(s$courses[s$schedulable], enrolment_count, 0L))
  capacity <- sum(vapply(s$rooms, `[[`, 0L, "capacity"))
  lines <- c(paste("LOAD max_exams", most, "students", sum(loads == most)), paste("SEATS demand", demand, "capacity", capacity, "min_slots", ceil_div(demand, capacity)),
    paste("HEURISTIC largest_degree slots", greedy_numbering(by_degree(s, s$schedulable), s$graph)), paste("HEURISTIC largest_enrolment slots", greedy_numbering(by_size(s, s$schedulable), s$graph)))
  table <- head(by_size(s, s$graph$vertices), 8L)
  lines <- c(lines, fixed_width_line("MATRIX", table, 9L, 9L))
  for (row in table) {
    cells <- vapply(table, function(column) if (row == column) "-" else as.character(s$graph$shared[row, column]), "")
    lines <- c(lines, fixed_width_line(row, cells, 9L, 9L))
  }
  lines
}
report_lines <- function(s) {
  cal <- s$calendar
  lines <- c(paste("INPUT courses", length(s$courses), "enrolments", sum(lengths(s$students)), "rooms", length(s$rooms), "students", length(s$students), "errors", length(s$errors)),
    if (length(s$errors)) paste("ERROR", s$errors) else character(), graph_lines(s), capacity_lines(s))
  for (id in s$empty) lines <- c(lines, paste("EMPTY", id))
  for (id in s$oversized) lines <- c(lines, paste("TOO_LARGE", id, "students", enrolment_count(s$courses[[id]]), "largest_room", s$largest_room))
  for (slot in sort(cal$closed)) lines <- c(lines, paste("CLOSED", slot_name(cal, slot)))
  for (id in ascii_sort(names(cal$fixed))) lines <- c(lines, paste("FIXED", id, slot_name(cal, cal$fixed[[id]])))
  for (pair in cal$orders) lines <- c(lines, paste("AFTER", pair[1L], pair[2L]))
  for (number in seq_along(s$attempts)) {
    attempt <- s$attempts[[number]]
    result <- if (is.null(attempt[[3L]])) "success" else paste("failed", attempt[[3L]])
    lines <- c(lines, paste("ATTEMPT", number, "courses", attempt[[1L]], "backtracks", attempt[[2L]], result))
  }
  for (number in seq_along(s$assignment_order)) {
    chosen <- s$assignment_order[[number]]
    lines <- c(lines, paste("ORDER", number, chosen[[1L]], slot_name(cal, chosen[[2L]]), "saturation", chosen[[3L]], "degree", degree(s$graph, chosen[[1L]])))
  }
  for (record in s$insertions) lines <- c(lines, paste("INSERTED", record[[1L]], slot_name(cal, record[[2L]]), "penalty", record[[3L]]))
  for (id in unscheduled(s)) {
    reason <- if (id %in% s$oversized) "too_large" else "no_slot"
    lines <- c(lines, paste("UNSCHEDULED", id, "reason", reason, "students", enrolment_count(s$courses[[id]])))
    for (slot in seq_along(s$reasons[[id]])) lines <- c(lines, paste(" ", slot_name(cal, slot), s$reasons[[id]][slot]))
  }
  c(lines, paste("SUMMARY scheduled", length(s$assignment), "unscheduled", length(unscheduled(s)), "slots_used", length(unique(s$assignment)), "penalty", s$penalty))
}

main <- function() {
  state <- list2env(list(errors = character()), parent = emptyenv())
  load_courses(file.path("input", "courses.csv"), state)
  load_enrolments(file.path("input", "enrolments.csv"), state)
  load_rooms(file.path("input", "rooms.csv"), state)
  lines <- read_lines("calendar.txt")
  s <- new_scheduler(state, new_calendar(lines))
  validate_calendar(s, lines)
  build_timetable(s)
  insert_excluded(s)
  exchange_slots(s)
  swap_chains(s)
  assign_rooms(s)
  write_files("output", list(timetable.txt = timetable_lines(s), rooms.csv = room_lines(s), penalties.txt = penalty_lines(s),
    student_schedules.txt = schedule_lines(s, read_lines("queries.txt")), course_status.csv = status_lines(s), report.txt = report_lines(s)))
  invisible(NULL)
}
main()
