types <- c("BUG", "TASK", "STORY")
priorities <- c("LOW", "MEDIUM", "HIGH", "CRITICAL")
workflows <- list(BUG = c("OPEN", "TRIAGED", "IN_PROGRESS", "REVIEW", "RESOLVED", "CLOSED", "REOPENED"),
                  TASK = c("OPEN", "IN_PROGRESS", "DONE"),
                  STORY = c("BACKLOG", "READY", "IN_PROGRESS", "REVIEW", "DONE"))
transitions <- list(
  BUG = c("OPEN TRIAGED", "TRIAGED IN_PROGRESS", "IN_PROGRESS REVIEW", "REVIEW IN_PROGRESS",
          "REVIEW RESOLVED", "RESOLVED CLOSED", "RESOLVED REOPENED", "CLOSED REOPENED", "REOPENED IN_PROGRESS"),
  TASK = c("OPEN IN_PROGRESS", "IN_PROGRESS OPEN", "IN_PROGRESS DONE"),
  STORY = c("BACKLOG READY", "READY BACKLOG", "READY IN_PROGRESS", "IN_PROGRESS REVIEW", "REVIEW IN_PROGRESS", "REVIEW DONE"))
done_states <- c("RESOLVED", "CLOSED", "DONE")
estimates <- c(0L, 1L, 2L, 3L, 5L, 8L, 13L, 21L)
equality_operators <- c("=", "!=")
order_operators <- c("=", "!=", "<", "<=", ">", ">=")
field_operators <- list(id = order_operators, type = equality_operators, status = equality_operators,
                        priority = order_operators, assignee = equality_operators, reviewer = equality_operators,
                        estimate = order_operators, sprint = equality_operators, comments = order_operators,
                        blocked = equality_operators, done = equality_operators, title = "~")
day <- 1L
users <- character()
issues <- list()
sprints <- list()
fail <- function(reason) {
  stop(structure(list(message = reason, call = NULL), class = c("command_error", "error", "condition")))
}
require_issue <- function(id) {
  if (!(id %in% names(issues))) fail("unknown issue")
  id
}
require_user <- function(user) {
  if (user != "-" && !(user %in% users)) fail("unknown user")
  user
}
require_sprint <- function(name) {
  if (!(name %in% names(sprints))) fail("unknown sprint")
  name
}
ordered_ids <- function(ids = names(issues)) ids[order(as.integer(ids))]
is_done <- function(id) issues[[id]]$state %in% done_states
not_done <- function(id) if (is_done(id)) fail("issue done")
points <- function(id) if (is.na(issues[[id]]$estimate)) 0L else issues[[id]]$estimate
display_estimate <- function(value) if (is.na(value)) "-" else as.character(value)
number_list <- function(ids) if (length(ids)) paste(ordered_ids(ids), collapse = ",") else "-"
yes_no <- function(value) if (value) "yes" else "no"
unfinished_blockers <- function(id) {
  ids <- ordered_ids(issues[[id]]$blockers)
  ids[!vapply(ids, is_done, logical(1))]
}
is_blocked <- function(id) !is_done(id) && length(unfinished_blockers(id)) > 0L
wip_count <- function(user) sum(vapply(issues, function(i) i$assignee == user && i$state == "IN_PROGRESS", logical(1)))
active_sprint <- function() {
  for (name in names(sprints)) if (sprints[[name]]$phase == "ACTIVE") return(name)
  "-"
}
members <- function(name) {
  ids <- ordered_ids()
  ids[vapply(ids, function(id) issues[[id]]$sprint == name, logical(1))]
}
remaining_points <- function(name) {
  ids <- members(name)
  sum(vapply(ids[!vapply(ids, is_done, logical(1))], points, integer(1)))
}
sprint_summary <- function(name) {
  ids <- members(name)
  paste("issues", length(ids), "points", sum(vapply(ids, points, integer(1))))
}
record <- function(id, content) issues[[id]]$history <<- c(issues[[id]]$history, paste("day", day, content))
blocked_states <- function(ids) setNames(vapply(ids, is_blocked, logical(1)), ids)
notifications <- function(before) {
  result <- character()
  for (id in ordered_ids(names(before))) {
    after <- is_blocked(id)
    if (after != before[[id]]) result <- c(result, paste(if (after) "BLOCKED" else "UNBLOCKED", id))
  }
  result
}
change_state <- function(id, target) {
  before <- blocked_states(issues[[id]]$blocks)
  previous <- issues[[id]]$state
  record(id, paste("MOVE", previous, target))
  issues[[id]]$state <<- target
  c(paste("MOVE", id, previous, target), notifications(before))
}
reaches <- function(start, goal) {
  pending <- start
  visited <- character()
  while (length(pending)) {
    id <- pending[length(pending)]
    pending <- head(pending, -1L)
    if (id == goal) return(TRUE)
    if (id %in% visited) next
    visited <- c(visited, id)
    pending <- c(pending, issues[[id]]$blocks)
  }
  FALSE
}
lower_ascii <- function(text) chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", text)
condition <- function(token) {
  field <- sub("^([a-z]*).*", "\\1", token)
  rest <- substring(token, nchar(field) + 1L)
  operator <- ""
  for (op in c(">=", "<=", "!=", "=", "<", ">", "~")) if (startsWith(rest, op)) {
    operator <- op
    break
  }
  value <- substring(rest, nchar(operator) + 1L)
  if (field == "" || operator == "" || value == "") fail(paste("syntax near", token))
  if (!(field %in% names(field_operators))) fail(paste("unknown field", field))
  if (!(operator %in% field_operators[[field]])) fail(paste("bad operator", token))
  valid <- FALSE
  if (field %in% c("assignee", "reviewer")) valid <- value == "-" || value %in% users
  if (field == "sprint") valid <- value == "-" || value %in% names(sprints)
  if (field %in% c("id", "estimate", "comments") && grepl("^[0-9]{1,6}$", value)) {
    value <- as.integer(value)
    valid <- TRUE
  } else if (field == "estimate" && value == "-" && operator %in% equality_operators) {
    value <- NA_integer_
    valid <- TRUE
  }
  if (field == "priority" && value %in% priorities) {
    value <- match(value, priorities)
    valid <- TRUE
  }
  if (field == "type") valid <- value %in% types
  if (field == "status") valid <- value %in% unlist(workflows, use.names = FALSE)
  if (field %in% c("blocked", "done")) valid <- value %in% c("yes", "no")
  if (field == "title") {
    value <- lower_ascii(value)
    valid <- TRUE
  }
  if (!valid) fail(paste("bad value", token))
  list(field = field, operator = operator, value = value)
}
parse_query <- function(text) {
  tokens <- regmatches(text, gregexpr("[()]|[^ ()]+", text))[[1]]
  conditions <- vector("list", length(tokens))
  operand <- TRUE
  depth <- 0L
  for (i in seq_along(tokens)) {
    token <- tokens[i]
    if (operand) {
      if (token == "(") depth <- depth + 1L
      else if (token %in% c("AND", "OR", ")")) fail(paste("syntax near", token))
      else if (token != "NOT") {
        conditions[[i]] <- condition(token)
        operand <- FALSE
      }
    } else if (token %in% c("AND", "OR")) operand <- TRUE
    else if (token == ")" && depth > 0L) depth <- depth - 1L
    else fail(paste("syntax near", token))
  }
  if (operand || depth != 0L) fail("syntax at end")
  position <- 1L
  accept <- function(token) {
    if (position <= length(tokens) && tokens[position] == token) {
      position <<- position + 1L
      return(TRUE)
    }
    FALSE
  }
  factor <- function() {
    if (accept("NOT")) return(list(op = "NOT", child = factor()))
    if (accept("(")) {
      node <- expression()
      accept(")")
      return(node)
    }
    node <- list(op = "condition", value = conditions[[position]])
    position <<- position + 1L
    node
  }
  term <- function() {
    node <- factor()
    while (accept("AND")) node <- list(op = "AND", left = node, right = factor())
    node
  }
  expression <- function() {
    node <- term()
    while (accept("OR")) node <- list(op = "OR", left = node, right = term())
    node
  }
  expression()
}
matches_query <- function(node, id) {
  if (node$op == "NOT") return(!matches_query(node$child, id))
  if (node$op == "AND") return(matches_query(node$left, id) && matches_query(node$right, id))
  if (node$op == "OR") return(matches_query(node$left, id) || matches_query(node$right, id))
  c <- node$value
  issue <- issues[[id]]
  actual <- switch(c$field, id = as.integer(id), type = issue$kind, status = issue$state,
                   priority = match(issue$priority, priorities), assignee = issue$assignee,
                   reviewer = issue$reviewer, estimate = issue$estimate, sprint = issue$sprint,
                   comments = issue$comments, blocked = yes_no(is_blocked(id)), done = yes_no(is_done(id)),
                   title = lower_ascii(issue$title))
  if (c$operator == "~") return(grepl(c$value, actual, fixed = TRUE))
  equal <- if (is.na(actual) || is.na(c$value)) is.na(actual) && is.na(c$value) else actual == c$value
  if (c$operator == "=") return(equal)
  if (c$operator == "!=") return(!equal)
  if (is.na(actual)) return(FALSE)
  switch(c$operator, "<" = actual < c$value, "<=" = actual <= c$value,
         ">" = actual > c$value, ">=" = actual >= c$value)
}
process_sprint <- function(words) {
  command <- words[2]
  name <- words[3]
  if (command == "NEW") {
    if (name %in% names(sprints)) fail("sprint exists")
    sprints[[name]] <<- list(phase = "PLANNED", start = NA_integer_, end = NA_integer_, velocity = 0L, records = integer())
    return(paste("SPRINT NEW", name))
  }
  require_sprint(name)
  if (command %in% c("ADD", "REMOVE")) {
    id <- require_issue(words[4])
    if (sprints[[name]]$phase == "ENDED") fail("sprint ended")
    if (command == "ADD") {
      not_done(id)
      old <- issues[[id]]$sprint
      if (old != "-" && sprints[[old]]$phase != "ENDED") fail(paste("in sprint", old))
      if (issues[[id]]$state == "BACKLOG") fail("not ready")
      issues[[id]]$sprint <<- name
    } else {
      if (issues[[id]]$sprint != name) fail("not in sprint")
      not_done(id)
      issues[[id]]$sprint <<- "-"
    }
    record(id, paste("SPRINT", command, name))
    return(paste("SPRINT", command, name, id, sprint_summary(name)))
  }
  if (command == "START") {
    if (sprints[[name]]$phase != "PLANNED") fail("sprint not planned")
    active <- active_sprint()
    if (active != "-") fail(paste("sprint active", active))
    if (!length(members(name))) fail("sprint empty")
    sprints[[name]]$phase <<- "ACTIVE"
    sprints[[name]]$start <<- day
    remaining <- remaining_points(name)
    sprints[[name]]$records[as.character(day)] <<- remaining
    return(paste("SPRINT START", name, "day", day, sprint_summary(name), "remaining", remaining))
  }
  if (sprints[[name]]$phase != "ACTIVE") fail("sprint not active")
  sprints[[name]]$records[as.character(day)] <<- remaining_points(name)
  ids <- members(name)
  finished <- ids[vapply(ids, is_done, logical(1))]
  returned <- ids[!vapply(ids, is_done, logical(1))]
  velocity <- sum(vapply(finished, points, integer(1)))
  sprints[[name]]$velocity <<- velocity
  sprints[[name]]$phase <<- "ENDED"
  sprints[[name]]$end <<- day
  result <- paste("SPRINT END", name, "day", day, "velocity", velocity, "done", length(finished), "returned", length(returned))
  for (id in returned) {
    issues[[id]]$sprint <<- "-"
    record(id, paste("SPRINT RETURN", name))
    result <- c(result, paste("RETURNED", id))
  }
  result
}
process_command <- function(line) {
  words <- strsplit(line, " ", fixed = TRUE)[[1]]
  command <- words[1]
  if (command == "DAY") {
    value <- as.integer(words[2])
    if (value < day) fail("day backwards")
    day <<- value
    return(paste("DAY", day))
  }
  if (command == "USER") {
    if (words[2] %in% users) fail("user exists")
    users <<- c(users, words[2])
    return(paste("USER", words[2]))
  }
  if (command == "CREATE") {
    id <- words[2]
    kind <- words[3]
    priority <- words[4]
    if (id %in% names(issues)) fail("issue exists")
    if (!(kind %in% types)) fail("bad type")
    if (!(priority %in% priorities)) fail("bad priority")
    issues[[id]] <<- list(kind = kind, priority = priority, title = paste(words[-seq_len(4L)], collapse = " "),
                          state = workflows[[kind]][1], assignee = "-", reviewer = "-", estimate = NA_integer_,
                          sprint = "-", comments = 0L, blocks = character(), blockers = character(), duplicate = "-",
                          duplicates = character(), history = character())
    record(id, paste("CREATE", kind, priority))
    return(paste("CREATE", id, kind, priority, issues[[id]]$state))
  }
  if (command == "SPRINT") return(process_sprint(words))
  if (command == "QUERY") {
    tree <- parse_query(paste(words[-1L], collapse = " "))
    ids <- ordered_ids()
    ids <- ids[vapply(ids, function(id) matches_query(tree, id), logical(1))]
    levels <- vapply(ids, function(id) match(issues[[id]]$priority, priorities), integer(1))
    ids <- ids[order(-levels, as.integer(ids))]
    lines <- vapply(ids, function(id) {
      i <- issues[[id]]
      paste(id, i$kind, i$priority, i$state, i$assignee, display_estimate(i$estimate), i$title)
    }, character(1))
    return(c(paste("QUERY", length(ids)), lines))
  }
  if (command == "BOARD") {
    result <- "BOARD"
    for (kind in types) {
      parts <- kind
      for (state in workflows[[kind]]) parts <- c(parts, state, sum(vapply(issues, function(i) i$kind == kind && i$state == state, logical(1))))
      result <- c(result, paste(parts, collapse = " "))
    }
    finished <- sum(vapply(ordered_ids(), is_done, logical(1)))
    return(c(result, paste("TOTAL", length(issues), "open", length(issues) - finished, "done", finished)))
  }
  if (command == "WORKLOAD") {
    result <- paste("WORKLOAD", length(users))
    for (user in sort(users, method = "radix")) {
      assigned <- ordered_ids()[vapply(ordered_ids(), function(id) issues[[id]]$assignee == user && !is_done(id), logical(1))]
      progress <- sum(vapply(assigned, function(id) issues[[id]]$state == "IN_PROGRESS", logical(1)))
      review <- sum(vapply(assigned, function(id) issues[[id]]$state == "REVIEW", logical(1)))
      reviewing <- sum(vapply(issues, function(i) i$reviewer == user && i$state == "REVIEW", logical(1)))
      result <- c(result, paste(user, "assigned", length(assigned), "in_progress", progress, "review", review, "reviewing", reviewing, "points", sum(vapply(assigned, points, integer(1)))))
    }
    return(result)
  }
  if (command == "SPRINTS") {
    result <- paste("SPRINTS", length(sprints))
    for (name in names(sprints)) {
      s <- sprints[[name]]
      line <- if (s$phase == "PLANNED") paste(name, s$phase, sprint_summary(name)) else if (s$phase == "ACTIVE") paste(name, s$phase, "start", s$start, sprint_summary(name), "remaining", remaining_points(name)) else paste(name, s$phase, "start", s$start, "end", s$end, "velocity", s$velocity)
      result <- c(result, line)
    }
    return(result)
  }
  if (command == "BURNDOWN") {
    name <- require_sprint(words[2])
    s <- sprints[[name]]
    if (s$phase == "PLANNED") fail("sprint not started")
    last <- if (s$phase == "ACTIVE") day else s$end
    result <- paste("BURNDOWN", name, s$phase, "days", last - s$start + 1L)
    value <- 0L
    for (d in seq.int(s$start, last)) {
      key <- as.character(d)
      if (key %in% names(s$records)) value <- s$records[[key]]
      result <- c(result, paste("day", d, value))
    }
    return(result)
  }
  if (command %in% c("LINK", "UNLINK")) {
    relation <- words[3]
    allowed <- if (command == "LINK") c("BLOCKS", "DUPLICATES") else "BLOCKS"
    if (!(relation %in% allowed)) fail("bad link")
    a <- require_issue(words[2])
    b <- require_issue(words[4])
    if (command == "UNLINK") {
      if (!(b %in% issues[[a]]$blocks)) fail("no link")
      before <- blocked_states(b)
      issues[[a]]$blocks <<- setdiff(issues[[a]]$blocks, b)
      issues[[b]]$blockers <<- setdiff(issues[[b]]$blockers, a)
      record(a, paste("UNLINK BLOCKS", b))
      record(b, paste("UNLINK BLOCKED_BY", a))
      return(c(paste("UNLINK", a, "BLOCKS", b), notifications(before)))
    }
    if (a == b) fail("self link")
    if (relation == "BLOCKS") {
      if (b %in% issues[[a]]$blocks) fail("link exists")
      if (reaches(b, a)) fail("cycle")
      not_done(b)
      before <- blocked_states(b)
      issues[[a]]$blocks <<- union(issues[[a]]$blocks, b)
      issues[[b]]$blockers <<- union(issues[[b]]$blockers, a)
      record(a, paste("LINK BLOCKS", b))
      record(b, paste("LINK BLOCKED_BY", a))
      return(c(paste("LINK", a, relation, b), notifications(before)))
    }
    if (issues[[a]]$kind != issues[[b]]$kind) fail("type mismatch")
    not_done(a)
    if (issues[[b]]$duplicate != "-") fail("target is duplicate")
    issues[[a]]$duplicate <<- b
    issues[[b]]$duplicates <<- union(issues[[b]]$duplicates, a)
    record(a, paste("LINK DUPLICATES", b))
    record(b, paste("LINK DUPLICATED_BY", a))
    result <- c(paste("LINK", a, relation, b), change_state(a, if (issues[[a]]$kind == "BUG") "CLOSED" else "DONE"))
    old <- issues[[a]]$sprint
    if (old != "-" && sprints[[old]]$phase != "ENDED") {
      issues[[a]]$sprint <<- "-"
      record(a, paste("SPRINT REMOVE", old))
    }
    return(result)
  }
  id <- require_issue(words[2])
  i <- issues[[id]]
  value <- if (length(words) >= 3L) words[3] else ""
  if (command == "SHOW") return(c(
    paste("ISSUE", id, i$kind, i$priority, i$state, "blocked", yes_no(is_blocked(id))),
    paste("TITLE", i$title), paste("PEOPLE assignee", i$assignee, "reviewer", i$reviewer),
    paste("PLAN estimate", display_estimate(i$estimate), "sprint", i$sprint, "comments", i$comments),
    paste("LINKS blocks", number_list(i$blocks), "blocked_by", number_list(i$blockers), "duplicate_of", i$duplicate, "duplicated_by", number_list(i$duplicates))))
  if (command == "HISTORY") return(c(paste("HISTORY", id, length(i$history)), i$history))
  if (command == "COMMENT") {
    require_user(value)
    issues[[id]]$comments <<- i$comments + 1L
    record(id, paste("COMMENT", value, paste(words[-seq_len(3L)], collapse = " ")))
    return(paste("COMMENT", id, i$comments + 1L))
  }
  if (command == "PRIORITY") {
    if (!(value %in% priorities)) fail("bad priority")
    not_done(id)
    if (value == i$priority) fail("no change")
    issues[[id]]$priority <<- value
    record(id, paste("PRIORITY", i$priority, value))
    return(paste("PRIORITY", id, i$priority, value))
  }
  if (command %in% c("ASSIGN", "REVIEWER")) {
    require_user(value)
    not_done(id)
    current <- if (command == "ASSIGN") i$assignee else i$reviewer
    if (value == current) fail("no change")
    if (command == "ASSIGN") {
      if (value == "-" && i$state %in% c("IN_PROGRESS", "REVIEW")) fail("assignee required")
      if (i$state == "IN_PROGRESS" && wip_count(value) >= 3L) fail(paste("wip limit", value))
      if (i$state == "REVIEW" && value == i$reviewer) fail("reviewer is assignee")
      issues[[id]]$assignee <<- value
    } else {
      if (value == "-" && i$state == "REVIEW") fail("reviewer required")
      if (i$state == "REVIEW" && value == i$assignee) fail("reviewer is assignee")
      issues[[id]]$reviewer <<- value
    }
    record(id, paste(command, value))
    return(paste(command, id, value))
  }
  if (command == "ESTIMATE") {
    value <- as.integer(value)
    if (!(value %in% estimates)) fail("bad estimate")
    not_done(id)
    if (!is.na(i$estimate) && value == i$estimate) fail("no change")
    previous <- display_estimate(i$estimate)
    issues[[id]]$estimate <<- value
    record(id, paste("ESTIMATE", previous, value))
    return(paste("ESTIMATE", id, previous, value))
  }
  if (i$duplicate != "-") fail(paste("duplicate of", i$duplicate))
  if (!(value %in% workflows[[i$kind]])) fail("bad state")
  if (!(paste(i$state, value) %in% transitions[[i$kind]])) fail(paste("cannot move", i$state, "to", value))
  if (value == "IN_PROGRESS") {
    active <- active_sprint()
    if (i$kind == "STORY" && (active == "-" || i$sprint != active)) fail("not in active sprint")
    if (i$assignee == "-") fail("no assignee")
    if (wip_count(i$assignee) >= 3L) fail(paste("wip limit", i$assignee))
  }
  if (value == "REVIEW") {
    if (i$reviewer == "-") fail("no reviewer")
    if (i$reviewer == i$assignee) fail("reviewer is assignee")
  }
  if (value %in% c("DONE", "RESOLVED")) {
    blockers <- unfinished_blockers(id)
    if (length(blockers)) fail(paste("blocked by", blockers[1]))
  }
  if (value == "READY" && is.na(i$estimate)) fail("no estimate")
  change_state(id, value)
}
input <- readLines(file("stdin"), warn = FALSE)
count <- as.integer(input[1])
output <- character()
for (i in seq_len(count)) {
  lines <- tryCatch(process_command(input[i + 1L]), command_error = function(e) paste("ERROR", e$message))
  output <- c(output, lines)
  active <- active_sprint()
  if (active != "-") sprints[[active]]$records[as.character(day)] <- remaining_points(active)
}
writeLines(output)
