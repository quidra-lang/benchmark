days <- c("MO", "TU", "WE", "TH", "FR", "SA", "SU")
grade_points <- c(A = 4, B = 3, C = 2, D = 1, F = 0)
courses <- new.env(parent = emptyenv(), hash = TRUE)
students <- new.env(parent = emptyenv(), hash = TRUE)
output <- character()
command_number <- 0

object <- function(...) list2env(list(...), parent = emptyenv())
has <- function(env, key) exists(key, envir = env, inherits = FALSE)
fetch <- function(env, key) get(key, envir = env, inherits = FALSE)
sorted <- function(values) sort(values, method = "radix")
keys <- function(env) sorted(ls(envir = env, all.names = TRUE))
fail <- function(message) stop(message, call. = FALSE)

emit <- function(..., indent = 0) {
  parts <- as.character(unlist(list(...), use.names = FALSE))
  output <<- c(output, paste0(strrep(" ", indent), paste(parts, collapse = " ")))
}

time_text <- function(minutes) sprintf("%02d:%02d", minutes %/% 60, minutes %% 60)
rate_text <- function(enrolled, capacity) {
  if (capacity == 0) "n/a" else paste0(enrolled * 100 %/% capacity, "%")
}
course_word <- function(word) grepl("^[A-Z]{2,4}[0-9]{3}$", word)
year_word <- function(word) grepl("^Y[1-9]$", word)

expression <- function(kind, children = list(), word = "") {
  references <- character()
  if (kind == "WORD" && !year_word(word)) references <- word
  for (child in children) references <- union(references, child$references)
  list(kind = kind, children = children, word = word, references = references)
}

combine <- function(kind, children) {
  flat <- list()
  for (child in children) {
    if (child$kind == kind)
      flat <- c(flat, child$children)
    else
      flat[[length(flat) + 1]] <- child
  }
  if (length(flat) == 1) flat[[1]] else expression(kind, flat)
}

parse_prerequisite <- function(code, text) {
  if (text == "-") return(expression("TRUE"))
  tokens <- regmatches(text, gregexpr("[A-Z0-9]+|[&|()]", text))[[1]]
  at <- 1

  if (length(tokens) == 0) fail(paste("invalid prereq", code))
  for (token in tokens) {
    if (!(token %in% c("&", "|", "(", ")")) &&
        !(course_word(token) || year_word(token)))
      fail(paste("invalid prereq", code))
  }
  peek <- function() {
    if (at > length(tokens)) "" else tokens[at]
  }
  parse_factor <- NULL
  parse_term <- NULL
  parse_expression <- NULL

  parse_factor <- function() {
    token <- peek()
    if (token == "" || token %in% c("&", "|", ")"))
      fail(paste("invalid prereq", code))
    at <<- at + 1
    if (token == "(") {
      value <- parse_expression()
      if (peek() != ")") fail(paste("invalid prereq", code))
      at <<- at + 1
      return(value)
    }
    expression("WORD", word = token)
  }
  parse_term <- function() {
    children <- list(parse_factor())
    while (peek() == "&") {
      at <<- at + 1
      children[[length(children) + 1]] <- parse_factor()
    }
    combine("AND", children)
  }
  parse_expression <- function() {
    children <- list(parse_term())
    while (peek() == "|") {
      at <<- at + 1
      children[[length(children) + 1]] <- parse_term()
    }
    combine("OR", children)
  }
  result <- parse_expression()
  if (at <= length(tokens)) fail(paste("invalid prereq", code))
  if (code %in% result$references) fail(paste("self prereq", code))
  result
}

canonical <- function(node) {
  if (node$kind == "TRUE") return("-")
  if (node$kind == "WORD") return(node$word)
  children <- vapply(node$children, function(child) {
    text <- canonical(child)
    if (node$kind == "AND" && child$kind == "OR")
      text <- paste0("(", text, ")")
    text
  }, character(1))
  paste(children, collapse = if (node$kind == "AND") "&" else "|")
}

satisfied <- function(node, student) {
  if (node$kind == "TRUE") return(TRUE)
  if (node$kind == "WORD") {
    if (year_word(node$word)) return(student$year >= as.numeric(substr(node$word, 2, 2)))
    return(node$word %in% names(student$passed))
  }
  results <- vapply(node$children, satisfied, logical(1), student = student)
  if (node$kind == "AND") all(results) else any(results)
}

parse_slot <- function(text) {
  day <- substr(text, 1, 2)
  sh <- as.integer(substr(text, 3, 4))
  sm <- as.integer(substr(text, 5, 6))
  eh <- as.integer(substr(text, 8, 9))
  em <- as.integer(substr(text, 10, 11))
  start <- sh * 60 + sm
  end <- eh * 60 + em
  if (!(day %in% days) || sh > 23 || sm > 59 || eh > 23 || em > 59 ||
      start >= end)
    fail(paste("invalid slot", text))
  list(day = match(day, days), start = start, end = end, original = text)
}

overlap <- function(a, b) {
  a$day == b$day && a$start < b$end && b$start < a$end
}

slot_text <- function(slot) paste0(time_text(slot$start), "-", time_text(slot$end))
weekly <- function(course) {
  sum(vapply(course$slots, function(slot) slot$end - slot$start, numeric(1)))
}
department <- function(code) substr(code, 1, nchar(code) - 3)
status <- function(course) if (course$open) "open" else "closed"

make_student <- function(id, year, limit, records) {
  passed <- character()
  for (code in names(records)) {
    if (records[[code]]$grade %in% c("A", "B", "C"))
      passed[code] <- records[[code]]$grade
  }
  object(
    id = id, year = year, limit = limit, records = records, passed = passed,
    courses = character(), waiting = character(), credits = 0, history = list()
  )
}

earned <- function(student) {
  sum(vapply(student$records, function(record) {
    if (record$grade == "F") 0 else record$credits
  }, numeric(1)))
}

gpa <- function(student) {
  if (length(student$records) == 0) return("n/a")
  total_points <- 0
  total_credits <- 0
  for (record in student$records) {
    total_points <- total_points + grade_points[[record$grade]] * record$credits
    total_credits <- total_credits + record$credits
  }
  value <- (200 * total_points + total_credits) %/% (2 * total_credits)
  sprintf("%d.%02d", value %/% 100, value %% 100)
}

require_student <- function(id) {
  if (!has(students, id)) fail(paste("unknown student", id))
  fetch(students, id)
}

require_course <- function(code) {
  if (!has(courses, code)) fail(paste("unknown course", code))
  fetch(courses, code)
}

record <- function(student, event) {
  student$history[[length(student$history) + 1]] <- list(command_number, event)
}

conflict <- function(student, course, excluded = NULL) {
  candidates <- intersect(student$courses, course$conflicts)
  if (!is.null(excluded)) candidates <- setdiff(candidates, excluded)
  if (length(candidates)) sorted(candidates)[1] else NULL
}

decision <- function(kind, extra = character()) list(kind = kind, extra = extra)
decision_text <- function(result) paste(c(result$kind, result$extra), collapse = " ")

eligibility <- function(student, course, excluded = NULL) {
  if (!course$open) return(decision("course closed"))
  if (course$code %in% student$courses) return(decision("already enrolled"))
  if (course$code %in% student$waiting) return(decision("already waitlisted"))
  if (course$code %in% names(student$passed))
    return(decision("already completed", student$passed[[course$code]]))
  if (!satisfied(course$prerequisite, student)) return(decision("prereq not met"))
  occupied <- conflict(student, course, excluded)
  if (!is.null(occupied)) return(decision("time conflict", occupied))
  credits <- student$credits + course$credits
  if (!is.null(excluded)) credits <- credits - require_course(excluded)$credits
  if (credits > student$limit)
    return(decision("credit limit", c(credits, student$limit)))
  decision("OK")
}

wait_position <- function(student, course) {
  1 + sum(vapply(course$waitlist, function(id) fetch(students, id)$year >= student$year,
                 logical(1)))
}

request <- function(student, course) {
  result <- eligibility(student, course)
  if (result$kind != "OK") return(result)
  if (length(course$enrolled) < course$capacity) return(decision("enroll"))
  if (length(student$waiting) >= 3) return(decision("waitlist limit"))
  decision("waitlist", wait_position(student, course))
}

fail_request <- function(result, student, course) {
  fail(paste(c(result$kind, student$id, course$code, result$extra), collapse = " "))
}

enroll <- function(student, course) {
  course$enrolled <- union(course$enrolled, student$id)
  student$courses <- union(student$courses, course$code)
  student$credits <- student$credits + course$credits
}

withdraw <- function(student, course) {
  course$enrolled <- setdiff(course$enrolled, student$id)
  student$courses <- setdiff(student$courses, course$code)
  student$credits <- student$credits - course$credits
}

unlist_waiting <- function(student, course) {
  course$waitlist <- course$waitlist[course$waitlist != student$id]
  student$waiting <- setdiff(student$waiting, course$code)
}

promotion <- function() {
  for (code in keys(courses)) {
    course <- fetch(courses, code)
    if (!course$open) next
    for (id in course$waitlist) {
      if (length(course$enrolled) >= course$capacity) break
      student <- fetch(students, id)
      if (!is.null(conflict(student, course)) ||
          student$credits + course$credits > student$limit) next
      unlist_waiting(student, course)
      enroll(student, course)
      record(student, paste("promote", code))
      emit("PROMOTE", id, code, "enrolled",
           paste0(length(course$enrolled), "/", course$capacity),
           "credits", paste0(student$credits, "/", student$limit), indent = 2)
    }
  }
}

cmd_course <- function(a) {
  code <- a[1]
  if (has(courses, code)) fail(paste("duplicate course", code))
  slots <- list()
  if (a[4] != "-") {
    slots <- lapply(strsplit(a[4], ",", fixed = TRUE)[[1]], parse_slot)
  }
  if (length(slots) >= 2) {
    for (i in seq_len(length(slots) - 1)) {
      for (j in seq.int(i + 1, length(slots))) {
        if (overlap(slots[[i]], slots[[j]]))
          fail(paste("overlapping slots", slots[[i]]$original, slots[[j]]$original))
      }
    }
  }
  required <- parse_prerequisite(code, a[5])
  course <- object(
    code = code, credits = as.numeric(a[2]), capacity = as.numeric(a[3]),
    slots = slots, prerequisite = required, open = TRUE,
    enrolled = character(), waitlist = character(), conflicts = character()
  )
  for (other_code in keys(courses)) {
    other <- fetch(courses, other_code)
    overlaps <- any(vapply(course$slots, function(first) {
      any(vapply(other$slots, function(second) overlap(first, second), logical(1)))
    }, logical(1)))
    if (overlaps) {
      course$conflicts <- union(course$conflicts, other_code)
      other$conflicts <- union(other$conflicts, code)
    }
  }
  assign(code, course, envir = courses)
  emit("COURSE", code, "credits", a[2], "capacity", a[3],
       "meetings", length(slots), "weekly", time_text(weekly(course)),
       "prereq", canonical(required))
}

cmd_student <- function(a) {
  id <- a[1]
  if (has(students, id)) fail(paste("duplicate student", id))
  records <- list()
  if (a[4] != "-") {
    for (text in strsplit(a[4], ",", fixed = TRUE)[[1]]) {
      fields <- strsplit(text, ":", fixed = TRUE)[[1]]
      code <- fields[1]
      grade <- fields[2]
      if (!(grade %in% names(grade_points)))
        fail(paste("invalid grade", id, code, grade))
      if (code %in% names(records))
        fail(paste("duplicate record", id, code))
      records[[code]] <- list(grade = grade, credits = as.numeric(fields[3]))
    }
  }
  student <- make_student(id, as.numeric(a[2]), as.numeric(a[3]), records)
  assign(id, student, envir = students)
  emit("STUDENT", id, "year", a[2], "limit", a[3],
       "records", length(records), "earned", earned(student), "gpa", gpa(student))
}

cmd_enroll <- function(a) {
  student <- require_student(a[1])
  course <- require_course(a[2])
  result <- request(student, course)
  if (!(result$kind %in% c("enroll", "waitlist"))) fail_request(result, student, course)
  if (result$kind == "enroll") {
    enroll(student, course)
    record(student, paste("enroll", course$code))
    emit("ENROLL", student$id, course$code, "enrolled",
         paste0(length(course$enrolled), "/", course$capacity),
         "credits", paste0(student$credits, "/", student$limit))
  } else {
    position <- as.integer(result$extra[1])
    course$waitlist <- append(course$waitlist, student$id, after = position - 1)
    student$waiting <- union(student$waiting, course$code)
    record(student, paste("waitlist", course$code, position))
    emit("ENROLL", student$id, course$code, "waitlist", position)
  }
}

cmd_check <- function(a) {
  student <- require_student(a[1])
  course <- require_course(a[2])
  emit("CHECK", student$id, course$code, decision_text(request(student, course)))
}

cmd_options <- function(a) {
  student <- require_student(a[1])
  emit("OPTIONS", student$id, "courses", length(keys(courses)))
  for (code in keys(courses)) {
    result <- request(student, fetch(courses, code))
    emit(code, decision_text(result), indent = 2)
  }
}

cmd_drop <- function(a) {
  student <- require_student(a[1])
  course <- require_course(a[2])
  if (course$code %in% student$courses) {
    withdraw(student, course)
    record(student, paste("drop", course$code))
    emit("DROP", student$id, course$code, "enrolled",
         paste0(length(course$enrolled), "/", course$capacity),
         "credits", paste0(student$credits, "/", student$limit))
  } else if (course$code %in% student$waiting) {
    unlist_waiting(student, course)
    record(student, paste("drop", course$code, "waitlist"))
    emit("DROP", student$id, course$code, "waitlist removed")
  } else {
    fail(paste("not registered", student$id, course$code))
  }
  promotion()
}

cmd_swap <- function(a) {
  student <- require_student(a[1])
  source <- require_course(a[2])
  destination <- require_course(a[3])
  if (!(source$code %in% student$courses))
    fail(paste("not enrolled", student$id, source$code))
  if (source$code == destination$code) fail(paste("same course", source$code))
  result <- eligibility(student, destination, source$code)
  if (result$kind != "OK") fail_request(result, student, destination)
  if (length(destination$enrolled) >= destination$capacity)
    fail(paste("course full", destination$code))
  withdraw(student, source)
  enroll(student, destination)
  record(student, paste("swap", source$code, destination$code))
  emit("SWAP", student$id, source$code, "->", destination$code,
       "credits", paste0(student$credits, "/", student$limit))
  promotion()
}

cmd_close <- function(a) {
  course <- require_course(a[1])
  if (!course$open) fail(paste("already closed", course$code))
  course$open <- FALSE
  emit("CLOSE", course$code, "enrolled",
       paste0(length(course$enrolled), "/", course$capacity),
       "waitlist", length(course$waitlist))
}

cmd_open <- function(a) {
  course <- require_course(a[1])
  if (course$open) fail(paste("already open", course$code))
  course$open <- TRUE
  emit("OPEN", course$code, "enrolled",
       paste0(length(course$enrolled), "/", course$capacity),
       "waitlist", length(course$waitlist))
  promotion()
}

cmd_capacity <- function(a) {
  course <- require_course(a[1])
  capacity <- as.numeric(a[2])
  if (capacity < length(course$enrolled))
    fail(paste("capacity below enrollment", course$code, length(course$enrolled)))
  previous <- course$capacity
  course$capacity <- capacity
  emit("CAPACITY", course$code, previous, "->", capacity)
  promotion()
}

cmd_limit <- function(a) {
  student <- require_student(a[1])
  limit <- as.numeric(a[2])
  if (limit < student$credits)
    fail(paste("limit below enrolled", student$id, student$credits))
  previous <- student$limit
  student$limit <- limit
  emit("LIMIT", student$id, previous, "->", limit)
  promotion()
}

cmd_prereq <- function(a) {
  course <- require_course(a[1])
  required <- parse_prerequisite(course$code, a[2])
  course$prerequisite <- required
  emit("PREREQ", course$code, canonical(required))
  for (id in course$waitlist) {
    student <- fetch(students, id)
    if (!satisfied(required, student)) {
      unlist_waiting(student, course)
      record(student, paste("unlist", course$code))
      emit("UNLIST", student$id, course$code, indent = 2)
    }
  }
}

cmd_cancel <- function(a) {
  course <- require_course(a[1])
  code <- course$code
  emit("CANCEL", code, "enrolled", length(course$enrolled),
       "waitlist", length(course$waitlist))
  for (id in course$enrolled) {
    student <- fetch(students, id)
    student$courses <- setdiff(student$courses, code)
    student$credits <- student$credits - course$credits
    record(student, paste("cancel", code))
  }
  for (id in course$waitlist) {
    student <- fetch(students, id)
    student$waiting <- setdiff(student$waiting, code)
    record(student, paste("cancel", code, "waitlist"))
  }
  for (other in course$conflicts) {
    remaining <- fetch(courses, other)
    remaining$conflicts <- setdiff(remaining$conflicts, code)
  }
  rm(list = code, envir = courses)
  promotion()
}

cmd_roster <- function(a) {
  course <- require_course(a[1])
  emit("ROSTER", course$code, status(course), "enrolled",
       paste0(length(course$enrolled), "/", course$capacity),
       "waitlist", length(course$waitlist))
  for (id in sorted(course$enrolled))
    emit("enrolled", id, "year", fetch(students, id)$year, indent = 2)
  for (i in seq_along(course$waitlist)) {
    id <- course$waitlist[i]
    emit("waitlist", i, id, "year", fetch(students, id)$year, indent = 2)
  }
}

student_slots <- function(student, day) {
  results <- list()
  for (code in student$courses) {
    for (slot in fetch(courses, code)$slots) {
      if (slot$day == day) {
        results[[length(results) + 1]] <-
          list(start = slot$start, end = slot$end, code = code)
      }
    }
  }
  if (length(results) <= 1) return(results)
  starts <- vapply(results, function(item) item$start, numeric(1))
  ends <- vapply(results, function(item) item$end, numeric(1))
  codes <- vapply(results, function(item) item$code, character(1))
  results[order(starts, ends, codes, method = "radix")]
}

cmd_schedule <- function(a) {
  student <- require_student(a[1])
  duration <- sum(vapply(student$courses, function(code)
    weekly(fetch(courses, code)), numeric(1)))
  emit("SCHEDULE", student$id, "courses", length(student$courses),
       "credits", student$credits, "weekly", time_text(duration))
  for (day in seq_along(days)) {
    slots <- student_slots(student, day)
    if (!length(slots)) next
    line <- days[day]
    for (slot in slots)
      line <- paste(line, slot_text(slot), slot$code)
    emit(line, indent = 2)
  }
  pending <- sorted(student$courses[vapply(student$courses, function(code)
    length(fetch(courses, code)$slots) == 0, logical(1))])
  if (length(pending)) emit("TBA", pending, indent = 2)
}

cmd_free <- function(a) {
  student <- require_student(a[1])
  if (!(a[2] %in% days)) fail(paste("invalid day", a[2]))
  slots <- student_slots(student, match(a[2], days))
  occupied <- list()
  for (slot in slots) {
    start <- max(480, slot$start)
    end <- min(1320, slot$end)
    if (start < end)
      occupied[[length(occupied) + 1]] <- c(start, end)
  }
  free <- list()
  cursor <- 480
  for (range in occupied) {
    if (cursor < range[1])
      free[[length(free) + 1]] <- c(cursor, range[1])
    cursor <- max(cursor, range[2])
  }
  if (cursor < 1320) free[[length(free) + 1]] <- c(cursor, 1320)
  total <- sum(vapply(free, function(range) range[2] - range[1], numeric(1)))
  intervals <- vapply(free, function(range)
    paste0(time_text(range[1]), "-", time_text(range[2])), character(1))
  emit("FREE", student$id, a[2], "total", time_text(total), intervals)
}

cmd_info <- function(a) {
  course <- require_course(a[1])
  emit("INFO", course$code, status(course), "credits", course$credits,
       "capacity", course$capacity, "prereq", canonical(course$prerequisite))
  slots <- course$slots
  if (length(slots)) {
    order_days <- vapply(slots, function(slot) slot$day, numeric(1))
    order_starts <- vapply(slots, function(slot) slot$start, numeric(1))
    for (i in order(order_days, order_starts)) {
      slot <- slots[[i]]
      emit("meet", days[slot$day], slot_text(slot), indent = 2)
    }
  } else {
    emit("meet TBA", indent = 2)
  }
  required_by <- keys(courses)[vapply(keys(courses), function(code)
    course$code %in% fetch(courses, code)$prerequisite$references, logical(1))]
  emit("required by", if (length(required_by)) required_by else "none", indent = 2)
}

cmd_audit <- function(a) {
  student <- require_student(a[1])
  emit("AUDIT", student$id, "year", student$year, "limit", student$limit)
  for (code in sorted(names(student$records))) {
    entry <- student$records[[code]]
    emit("record", code, entry$grade, entry$credits, indent = 2)
  }
  emit("earned", earned(student), "gpa", gpa(student), indent = 2)
  for (code in sorted(student$courses))
    emit("enrolled", code, fetch(courses, code)$credits, indent = 2)
  emit("credits", student$credits, "remaining", student$limit - student$credits, indent = 2)
  for (code in sorted(student$waiting))
    emit("waitlist", code, match(student$id, fetch(courses, code)$waitlist), indent = 2)
}

cmd_history <- function(a) {
  student <- require_student(a[1])
  emit("HISTORY", student$id, "events", length(student$history))
  for (entry in student$history)
    emit(entry[[1]], entry[[2]], indent = 2)
}

cmd_students <- function(a) {
  emit("STUDENTS", length(keys(students)))
  for (id in keys(students)) {
    student <- fetch(students, id)
    emit(id, "year", student$year, "credits",
         paste0(student$credits, "/", student$limit),
         "courses", length(student$courses),
         "waitlists", length(student$waiting), indent = 2)
  }
}

group_counts <- function(selected) {
  enrolled <- sum(vapply(selected, function(course) length(course$enrolled), numeric(1)))
  capacity <- sum(vapply(selected, function(course) course$capacity, numeric(1)))
  waitlisted <- sum(vapply(selected, function(course) length(course$waitlist), numeric(1)))
  c("enrolled", paste0(enrolled, "/", capacity),
    "rate", rate_text(enrolled, capacity), "waitlisted", waitlisted)
}

cmd_report <- function(a) {
  names <- keys(courses)
  all_courses <- lapply(names, function(code) fetch(courses, code))
  emit("REPORT", "courses", length(names), group_counts(all_courses))
  departments <- list()
  for (code in names) {
    course <- fetch(courses, code)
    emit(code, status(course),
         paste0(length(course$enrolled), "/", course$capacity),
         rate_text(length(course$enrolled), course$capacity),
         "waitlist", length(course$waitlist), indent = 2)
    dept <- department(code)
    departments[[dept]] <- c(departments[[dept]], list(course))
  }
  for (dept in sorted(names(departments))) {
    selected <- departments[[dept]]
    emit("dept", dept, "courses", length(selected), group_counts(selected), indent = 2)
  }
}

handlers <- list(
  COURSE = cmd_course, STUDENT = cmd_student, ENROLL = cmd_enroll,
  CHECK = cmd_check, OPTIONS = cmd_options, DROP = cmd_drop,
  SWAP = cmd_swap, CLOSE = cmd_close, OPEN = cmd_open,
  CAPACITY = cmd_capacity, LIMIT = cmd_limit, PREREQ = cmd_prereq,
  CANCEL = cmd_cancel, ROSTER = cmd_roster, SCHEDULE = cmd_schedule,
  FREE = cmd_free, INFO = cmd_info, AUDIT = cmd_audit,
  HISTORY = cmd_history, STUDENTS = cmd_students, REPORT = cmd_report
)

lines <- readLines(file("stdin"), warn = FALSE)
count <- as.integer(lines[1])
for (i in seq_len(count)) {
  command_number <- i
  values <- strsplit(lines[i + 1], " ", fixed = TRUE)[[1]]
  command <- values[1]
  args <- values[-1]
  tryCatch(handlers[[command]](args), error = function(error) {
    emit("ERROR", conditionMessage(error))
  })
}
if (length(output)) cat(paste0(paste(output, collapse = "\n"), "\n"))
