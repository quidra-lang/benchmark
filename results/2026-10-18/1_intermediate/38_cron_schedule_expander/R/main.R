field_names <- c("minute", "hour", "day-of-month", "month", "day-of-week")
minimum <- c(0L, 0L, 1L, 1L, 0L)
maximum <- c(59L, 23L, 31L, 12L, 7L)
months <- c("January", "February", "March", "April", "May", "June", "July", "August",
            "September", "October", "November", "December")
weekdays <- c("Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday")
macros <- c("@yearly" = "0 0 1 1 *", "@annually" = "0 0 1 1 *", "@monthly" = "0 0 1 * *",
            "@weekly" = "0 0 * * 0", "@daily" = "0 0 * * *", "@midnight" = "0 0 * * *", "@hourly" = "0 * * * *")
signatures <- list(REMOVE = "id", RENAME = c("id", "newid"), ENABLE = "id", DISABLE = "id",
  RUNTIME = c("id", "duration", "policy"), LIST = character(), EXPAND = c("id", "field"),
  DESCRIBE = "id", MATCH = c("id", "datetime"), NEXT = c("id", "datetime", "count"),
  PREV = c("id", "datetime", "count"), COUNT = c("id", "datetime", "datetime"),
  GAP = c("id", "datetime"), OVERLAP = c("id", "id", "datetime", "datetime"),
  TIMELINE = c("datetime", "datetime"), CONFLICTS = c("datetime", "datetime"), WEEK = "date",
  CALENDAR = c("id", "month"), SIMULATE = c("datetime", "datetime"), EXCLUDE = "date", INCLUDE = "date", HOLIDAYS = character())

fail <- function(message) {
  stop(structure(list(message = message, call = NULL), class = c("cron_error", "error", "condition")))
}
words <- function(text) strsplit(gsub("^ +| +$", "", text), " +")[[1L]]
joined <- function(values) paste(values, collapse = " ")
small_digits <- function(text) grepl("^[0-9]{1,2}$", text)
field_error <- function(field, reason) fail(paste(field_names[field], reason))
split_items <- function(text) {
  commas <- gregexpr(",", text, fixed = TRUE)[[1L]]
  if (commas[1L] < 0L) return(text)
  starts <- c(1L, commas + 1L)
  ends <- c(commas - 1L, nchar(text))
  vapply(seq_along(starts), function(i) substr(text, starts[i], ends[i]), character(1L))
}

leap <- function(year) year %% 4L == 0L && (year %% 100L != 0L || year %% 400L == 0L)
month_length <- function(year, month) {
  c(31L, 28L, 31L, 30L, 31L, 30L, 31L, 31L, 30L, 31L, 30L, 31L)[month] +
    as.integer(month == 2L && leap(year))
}
leap_count <- function(year) year %/% 4L - year %/% 100L + year %/% 400L
day_number <- function(year, month, day) {
  result <- 365L * (year - 2000L) + leap_count(year - 1L) - leap_count(1999L) + day - 1L
  for (prior in seq_len(month - 1L)) result <- result + month_length(year, prior)
  result
}
make_calendar <- function() {
  result <- matrix(0L, nrow = 36526L, ncol = 5L,
                   dimnames = list(NULL, c("year", "month", "day", "weekday", "length")))
  offset <- 0L
  for (year in 2000L:2099L) for (month in seq_len(12L)) {
    count <- month_length(year, month)
    days <- seq_len(count)
    result[offset + days, ] <- cbind(year, month, days, (offset + days + 5L) %% 7L, count)
    offset <- offset + count
  }
  result[36526L, ] <- c(2100L, 1L, 1L, 5L, 31L)
  result
}
date_plain <- function(day) {
  date <- calendar[day + 1L, ]
  sprintf("%04d-%02d-%02d", date[["year"]], date[["month"]], date[["day"]])
}
date_text <- function(day) paste(date_plain(day), substr(weekdays[(day + 6L) %% 7L + 1L], 1L, 3L))
clock_text <- function(minute) sprintf("%02d:%02d", minute %/% 60L, minute %% 60L)
datetime_text <- function(minute) {
  day <- minute %/% 1440L
  paste(date_plain(day), clock_text(minute %% 1440L), substr(weekdays[(day + 6L) %% 7L + 1L], 1L, 3L))
}
span_text <- function(minutes) sprintf("%dd%02dh%02dm", minutes %/% 1440L, minutes %% 1440L %/% 60L, minutes %% 60L)
date_argument <- function(text, reason = "invalid date") {
  if (!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", text)) fail(reason)
  year <- as.integer(substr(text, 1L, 4L))
  month <- as.integer(substr(text, 6L, 7L))
  day <- as.integer(substr(text, 9L, 10L))
  if (year < 2001L || year > 2098L || month < 1L || month > 12L || day < 1L || day > month_length(year, month)) fail(reason)
  day_number(year, month, day)
}
datetime_argument <- function(date, time) {
  day <- date_argument(date, "invalid datetime")
  if (!grepl("^[0-9]{2}:[0-9]{2}$", time)) fail("invalid datetime")
  hour <- as.integer(substr(time, 1L, 2L))
  minute <- as.integer(substr(time, 4L, 5L))
  if (hour > 23L || minute > 59L) fail("invalid datetime")
  day * 1440L + hour * 60L + minute
}
month_argument <- function(text) {
  if (!grepl("^[0-9]{4}-[0-9]{2}$", text)) fail("invalid month")
  year <- as.integer(substr(text, 1L, 4L))
  month <- as.integer(substr(text, 6L, 7L))
  if (year < 2001L || year > 2098L || month < 1L || month > 12L) fail("invalid month")
  day_number(year, month, 1L)
}
positive_argument <- function(text, width, maximum, reason) {
  if (nchar(text) > width || !grepl("^[1-9][0-9]*$", text)) fail(reason)
  value <- as.integer(text)
  if (value > maximum) fail(reason)
  value
}

field_value <- function(field, text) {
  names <- if (field == 4L) toupper(substr(months, 1L, 3L)) else if (field == 5L) toupper(substr(weekdays, 1L, 3L)) else character()
  index <- match(text, names)
  if (!is.na(index)) return(index - as.integer(field == 5L))
  if (!small_digits(text)) field_error(field, "invalid value")
  value <- as.integer(text)
  if (value < minimum[field] || value > maximum[field]) field_error(field, "out of range")
  value
}
special_number <- function(field, text, width, maximum) {
  if (!grepl(sprintf("^[0-9]{1,%d}$", width), text)) field_error(field, "invalid value")
  value <- as.integer(text)
  if (value < 1L || value > maximum) field_error(field, "out of range")
  value
}
new_special <- function(kind, value = 0L, nth = 0L) {
  text <- switch(kind, last = "L", workday = "LW", before = paste0("L-", value),
                 nearest = paste0(value, "W"), nth = paste0(value, "#", nth), weekday = paste0(value, "L"))
  list(kind = kind, value = value, nth = nth, text = text)
}
parse_field <- function(text, index) {
  values <- integer()
  specials <- list()
  for (item in split_items(text)) {
    if (item == "") field_error(index, "empty item")
    special <- NULL
    if (index == 3L && (startsWith(item, "L") || endsWith(item, "W"))) {
      special <- if (item == "L") new_special("last") else if (item == "LW") new_special("workday") else if (startsWith(item, "L-")) {
        new_special("before", special_number(index, substring(item, 3L), 2L, 30L))
      } else if (endsWith(item, "W")) {
        new_special("nearest", special_number(index, substr(item, 1L, nchar(item) - 1L), 2L, 31L))
      } else field_error(index, "invalid value")
    } else if (index == 5L && grepl("#", item, fixed = TRUE)) {
      hash <- regexpr("#", item, fixed = TRUE)[[1L]]
      value <- field_value(index, substr(item, 1L, hash - 1L))
      nth <- special_number(index, substring(item, hash + 1L), 1L, 5L)
      special <- new_special("nth", value %% 7L, nth)
    } else if (index == 5L && nchar(item) >= 2L && endsWith(item, "L")) {
      value <- field_value(index, substr(item, 1L, nchar(item) - 1L))
      special <- new_special("weekday", value %% 7L)
    } else {
      slash <- regexpr("/", item, fixed = TRUE)[[1L]]
      base <- if (slash < 0L) item else substr(item, 1L, slash - 1L)
      dash <- regexpr("-", base, fixed = TRUE)[[1L]]
      if (base == "*") {
        first <- minimum[index]
        last <- maximum[index]
      } else if (dash > 0L) {
        first <- field_value(index, substr(base, 1L, dash - 1L))
        last <- field_value(index, substring(base, dash + 1L))
        if (first > last) field_error(index, "invalid range")
      } else {
        first <- field_value(index, base)
        last <- if (slash < 0L) first else maximum[index]
      }
      step <- 1L
      if (slash > 0L) {
        part <- substring(item, slash + 1L)
        if (!small_digits(part)) field_error(index, "invalid step")
        step <- as.integer(part)
        if (step == 0L) field_error(index, "invalid step")
      }
      expanded <- seq.int(first, last, by = step)
      if (index == 5L) expanded <- expanded %% 7L
      values <- c(values, expanded)
    }
    if (!is.null(special) && !special$text %in% vapply(specials, function(s) s$text, character(1L))) specials <- c(specials, list(special))
  }
  list(index = index, values = sort(unique(values), method = "radix"), specials = specials, restricted = !startsWith(text, "*"))
}
parse_cron <- function(tokens) {
  text <- joined(tokens)
  if (length(tokens) == 1L && startsWith(tokens, "@")) {
    if (!tokens %in% names(macros)) fail("unknown macro")
    tokens <- words(macros[[tokens]])
  }
  if (length(tokens) != 5L) fail("field count")
  fields <- lapply(seq_len(5L), function(index) parse_field(tokens[index], index))
  minutes <- fields[[1L]]$values
  hours <- fields[[2L]]$values
  times <- rep(hours, each = length(minutes)) * 60L + rep(minutes, times = length(hours))
  list(text = text, expanded = joined(tokens), fields = fields,
       disjunction = fields[[3L]]$restricted && fields[[5L]]$restricted, times = times)
}

nearest_workday <- function(first, day, length) {
  weekday <- (first + day + 5L) %% 7L
  if (weekday == 6L) return(if (day == 1L) 3L else day - 1L)
  if (weekday == 0L) return(if (day == length) day - 2L else day + 1L)
  day
}
day_status <- function(cron, day) {
  date <- calendar[day + 1L, ]
  month <- date[["month"]]
  d <- date[["day"]]
  e <- date[["length"]]
  w <- date[["weekday"]]
  first <- day - d + 1L
  dom <- d %in% cron$fields[[3L]]$values
  dow <- w %in% cron$fields[[5L]]$values
  for (special in cron$fields[[3L]]$specials) {
    target <- switch(special$kind, last = e, workday = nearest_workday(first, e, e),
      before = e - special$value, nearest = if (special$value <= e) nearest_workday(first, special$value, e) else 0L)
    dom <- dom || d == target
  }
  for (special in cron$fields[[5L]]$specials) {
    matches <- if (special$kind == "nth") (d - 1L) %/% 7L + 1L == special$nth else d + 7L > e
    dow <- dow || (w == special$value && matches)
  }
  c(month = month %in% cron$fields[[4L]]$values, dom = dom, dow = dow,
    condition = if (cron$disjunction) dom || dow else dom && dow)
}
scheduled_day <- function(cron, day) {
  status <- day_status(cron, day)
  status[["month"]] && status[["condition"]]
}
fire_times <- function(job, lo, hi, holidays, reverse = FALSE, limit = 0L) {
  days <- seq.int(lo %/% 1440L, hi %/% 1440L)
  daily <- job$cron$times
  if (reverse) {
    days <- rev(days)
    daily <- rev(daily)
  }
  result <- integer()
  for (day in days) {
    if (day %in% holidays || !scheduled_day(job$cron, day)) next
    times <- day * 1440L + daily
    result <- c(result, times[lo <= times & times <= hi])
    if (limit > 0L && length(result) >= limit) return(head(result, limit))
  }
  result
}

word_list <- function(parts, either = FALSE) {
  if (length(parts) < 2L) return(paste(parts, collapse = ""))
  paste0(paste(head(parts, -1L), collapse = ", "), if (either) " or " else " and ", tail(parts, 1L))
}
value_name <- function(index, value) {
  if (index == 4L) months[value] else if (index == 5L) weekdays[value + 1L] else as.character(value)
}
value_list <- function(field, either = FALSE) {
  values <- field$values
  parts <- character()
  first <- 1L
  while (first <= length(values)) {
    last <- first
    while (last < length(values) && values[last + 1L] == values[last] + 1L) last <- last + 1L
    if (last - first >= 2L) parts <- c(parts, paste(value_name(field$index, values[first]), "through", value_name(field$index, values[last]))) else {
      parts <- c(parts, value_name(field$index, values[first:last]))
    }
    first <- last + 1L
  }
  word_list(parts, either)
}
stepped <- function(field) {
  values <- field$values
  if (length(values) < 2L || values[1L] != 0L || values[2L] < 2L) return(0L)
  step <- values[2L]
  if (length(values) == maximum[field$index] %/% step + 1L && all(values == (seq_along(values) - 1L) * step)) step else 0L
}
dom_phrase <- function(field) {
  parts <- character()
  if (length(field$values)) parts <- paste(if (length(field$values) == 1L) "day" else "days", value_list(field))
  for (special in field$specials) {
    parts <- c(parts, switch(special$kind, last = "the last day", workday = "the last weekday",
      before = paste(special$value, if (special$value == 1L) "day" else "days", "before the last day"),
      nearest = paste("the weekday nearest day", special$value)))
  }
  paste0(word_list(parts), " of the month")
}
dow_phrase <- function(field, either = FALSE) {
  parts <- if (length(field$values)) value_list(field, either) else character()
  for (special in field$specials) {
    name <- weekdays[special$value + 1L]
    parts <- c(parts, if (special$kind == "nth") paste("the", c("1st", "2nd", "3rd", "4th", "5th")[special$nth], name) else paste("the last", name))
  }
  paste0(word_list(parts, either), if (length(field$specials)) " of the month" else "")
}
description <- function(cron) {
  minute <- cron$fields[[1L]]
  hour <- cron$fields[[2L]]
  if (length(cron$times) <= 4L) {
    result <- paste0("At ", word_list(clock_text(cron$times)))
  } else {
    ms <- stepped(minute)
    hs <- stepped(hour)
    result <- if (length(minute$values) == 60L) "Every minute" else if (ms > 0L) paste("Every", ms, "minutes") else if (length(minute$values) == 1L) {
      paste("At minute", minute$values[1L])
    } else paste0("At minutes ", value_list(minute))
    if (length(hour$values) == 24L) {
      if (startsWith(result, "At minute")) result <- paste0(result, " of every hour")
    } else if (hs > 0L) result <- paste0(result, ", every ", hs, " hours") else {
      first <- head(hour$values, 1L)
      last <- tail(hour$values, 1L)
      result <- paste0(result, if (last - first + 1L == length(hour$values)) sprintf(", between %02d:00 and %02d:59", first, last) else paste0(", during hours ", value_list(hour)))
    }
  }
  dom <- cron$fields[[3L]]
  dow <- cron$fields[[5L]]
  dfull <- length(dom$values) == 31L
  ufull <- length(dow$values) == 7L
  if (cron$disjunction) {
    if (!dfull && !ufull) result <- paste0(result, ", on ", dom_phrase(dom), " or on ", dow_phrase(dow))
  } else if (!dfull && !ufull) result <- paste0(result, ", on ", dom_phrase(dom), " if it is ", dow_phrase(dow, TRUE)) else if (!dfull) {
    result <- paste0(result, ", on ", dom_phrase(dom))
  } else if (!ufull) result <- paste0(result, ", on ", dow_phrase(dow))
  if (length(cron$fields[[4L]]$values) != 12L) result <- paste0(result, ", in ", value_list(cron$fields[[4L]]))
  result
}

new_id <- function(state, id) {
  if (!grepl("^[a-z][a-z0-9_]{0,15}$", id)) fail("invalid id")
  if (!is.null(state$jobs[[id]])) fail("duplicate job")
  id
}
job_argument <- function(state, id) {
  job <- state$jobs[[id]]
  if (is.null(job)) fail("unknown job")
  job
}
ordered_jobs <- function(state, enabled_only = FALSE) {
  result <- state$jobs[sort(names(state$jobs), method = "radix")]
  if (enabled_only) result <- Filter(function(job) job$enabled, result)
  result
}
parse_arguments <- function(state, types, tokens) {
  values <- list()
  datetimes <- integer()
  position <- 1L
  for (type in types) {
    token <- tokens[position]
    value <- switch(type,
      id = job_argument(state, token), newid = new_id(state, token),
      datetime = datetime_argument(token, tokens[position + 1L]),
      date = date_argument(token), month = month_argument(token),
      field = {
        index <- match(token, field_names)
        if (is.na(index)) fail("invalid field")
        index
      },
      count = positive_argument(token, 2L, 50L, "invalid count"),
      duration = positive_argument(token, 4L, 1440L, "invalid duration"),
      policy = {
        if (!token %in% c("ALLOW", "FORBID", "REPLACE")) fail("invalid policy")
        token
      })
    values[[length(values) + 1L]] <- value
    if (type == "datetime") datetimes <- c(datetimes, value)
    position <- position + if (type == "datetime") 2L else 1L
  }
  if (length(datetimes) == 2L) {
    if (datetimes[1L] > datetimes[2L]) fail("invalid window")
    if (datetimes[2L] - datetimes[1L] > 44640L) fail("window too long")
  }
  values
}
fire_table <- function(state, lo, hi) {
  jobs <- ordered_jobs(state, TRUE)
  incidence <- matrix(FALSE, nrow = length(jobs), ncol = hi - lo + 1L)
  counts <- integer(hi - lo + 1L)
  for (index in seq_along(jobs)) {
    positions <- fire_times(jobs[[index]], lo, hi, state$holidays) - lo + 1L
    incidence[index, positions] <- TRUE
    counts[positions] <- counts[positions] + 1L
  }
  list(jobs = jobs, incidence = incidence, counts = counts)
}
combined_report <- function(state, command, lo, hi) {
  data <- fire_table(state, lo, hi)
  if (command == "TIMELINE") {
    pairs <- which(data$incidence, arr.ind = TRUE)
    count <- nrow(pairs)
    rows <- paste("TIMELINE", count)
    for (index in seq_len(min(100L, count))) {
      rows <- c(rows, paste(datetime_text(lo + pairs[index, 2L] - 1L), data$jobs[[pairs[index, 1L]]]$id))
    }
  } else {
    positions <- which(data$counts >= 2L)
    count <- length(positions)
    rows <- paste("CONFLICTS", count, "peak", if (count) max(data$counts[positions]) else 0L)
    for (position in head(positions, 100L)) {
      ids <- names(data$jobs)[data$incidence[, position]]
      rows <- c(rows, paste(datetime_text(lo + position - 1L), data$counts[position], joined(ids)))
    }
  }
  if (count > 100L) rows <- c(rows, paste("...", count - 100L, "more"))
  rows
}
week_report <- function(state, first, original) {
  jobs <- ordered_jobs(state, TRUE)
  counts <- integer(168L)
  for (offset in 0L:6L) {
    day <- first + offset
    if (day %in% state$holidays) next
    for (job in jobs) if (scheduled_day(job$cron, day)) {
      positions <- offset * 24L + job$cron$fields[[2L]]$values + 1L
      counts[positions] <- counts[positions] + length(job$cron$fields[[1L]]$values)
    }
  }
  rows <- paste("WEEK", original, sum(counts))
  for (offset in 0L:6L) {
    hourly <- counts[offset * 24L + seq_len(24L)]
    marks <- ifelse(hourly == 0L, ".", ifelse(hourly < 10L, as.character(hourly), "+"))
    rows <- c(rows, paste(date_text(first + offset), paste(marks, collapse = ""), sum(hourly)))
  }
  rows
}
calendar_report <- function(state, job, first, original) {
  days <- seq_len(calendar[first + 1L, "length"])
  scheduled <- vapply(first + days - 1L, function(day) scheduled_day(job$cron, day), logical(1L))
  marks <- ifelse(scheduled, ifelse((first + days - 1L) %in% state$holidays, "x", "*"), "-")
  count <- sum(marks == "*")
  cells <- c(rep("...", (first + 6L) %% 7L), sprintf("%02d%s", days, marks))
  cells <- c(cells, rep("...", (7L - length(cells) %% 7L) %% 7L))
  rows <- c(paste("CALENDAR", job$id, original, "days", count, "runs", count * length(job$cron$times)),
            "Sun Mon Tue Wed Thu Fri Sat")
  for (start in seq.int(1L, length(cells), by = 7L)) rows <- c(rows, joined(cells[start + 0L:6L]))
  rows
}
simulation_report <- function(state, lo, hi) {
  jobs <- ordered_jobs(state, TRUE)
  events <- integer(hi - lo + 1441L)
  details <- character()
  for (job in jobs) {
    times <- fire_times(job, lo, hi, state$holidays)
    starts <- times
    ends <- times + job$duration
    skipped <- 0L
    replaced <- 0L
    if (job$policy == "FORBID") {
      accepted <- 0L
      last_end <- lo
      for (time in times) if (time >= last_end) {
        accepted <- accepted + 1L
        starts[accepted] <- time
        last_end <- time + job$duration
        ends[accepted] <- last_end
      }
      starts <- starts[seq_len(accepted)]
      ends <- ends[seq_len(accepted)]
      skipped <- length(times) - accepted
    } else if (job$policy == "REPLACE" && length(times) > 1L) {
      next_start <- tail(starts, -1L)
      previous_end <- head(ends, -1L)
      replaced <- sum(previous_end > next_start)
      ends <- c(pmin(previous_end, next_start), tail(ends, 1L))
    }
    events <- events + tabulate(starts - lo + 1L, nbins = length(events)) - tabulate(ends - lo + 1L, nbins = length(events))
    details <- c(details, paste(job$id, job$policy, "started", length(starts), "skipped", skipped,
                               "replaced", replaced, "busy", sum(ends - starts)))
  }
  running <- cumsum(events)
  peak <- max(running)
  header <- paste("SIMULATE", length(jobs), "peak", peak)
  if (peak > 0L) header <- paste(header, "at", datetime_text(lo + which.max(running) - 1L))
  c(header, details)
}

execute <- function(state, line) {
  tokens <- words(line)
  command <- tokens[1L]
  tokens <- tokens[-1L]
  if (!command %in% c("JOB", "VALIDATE", names(signatures))) fail("unknown command")
  if (command %in% c("JOB", "VALIDATE")) {
    if (length(tokens) < if (command == "JOB") 2L else 1L) fail("wrong arguments")
    if (command == "JOB") {
      id <- new_id(state, tokens[1L])
      cron <- parse_cron(tokens[-1L])
      state$jobs[[id]] <- list(id = id, cron = cron, enabled = TRUE, duration = 1L, policy = "ALLOW")
      return(paste("JOB", id, "added"))
    }
    cron <- parse_cron(tokens)
    return(paste("VALID", cron$expanded, if (cron$disjunction) "OR" else "AND", length(cron$times)))
  }
  types <- signatures[[command]]
  if (length(tokens) != sum(ifelse(types == "datetime", 2L, 1L))) fail("wrong arguments")
  args <- parse_arguments(state, types, tokens)
  if (length(types) && types[1L] == "id") job <- args[[1L]]
  switch(command,
    REMOVE = {
      state$jobs[[job$id]] <- NULL
      paste("REMOVE", job$id)
    },
    RENAME = {
      old_id <- job$id
      job$id <- args[[2L]]
      state$jobs[[old_id]] <- NULL
      state$jobs[[job$id]] <- job
      paste("RENAME", old_id, job$id)
    },
    ENABLE =, DISABLE = {
      enabled <- command == "ENABLE"
      if (job$enabled == enabled) fail(if (enabled) "already enabled" else "already disabled")
      job$enabled <- enabled
      state$jobs[[job$id]] <- job
      paste(command, job$id)
    },
    RUNTIME = {
      job$duration <- args[[2L]]
      job$policy <- args[[3L]]
      state$jobs[[job$id]] <- job
      paste("RUNTIME", job$id, job$duration, job$policy)
    },
    LIST = {
      jobs <- ordered_jobs(state)
      c(paste("LIST", length(jobs)), vapply(jobs, function(job) {
        paste(job$id, if (job$enabled) "on" else "off", job$duration, job$policy, job$cron$text)
      }, character(1L)))
    },
    EXPAND = {
      field <- job$cron$fields[[args[[2L]]]]
      joined(c("EXPAND", job$id, field_names[args[[2L]]], length(field$values), field$values,
               vapply(field$specials, function(special) special$text, character(1L))))
    },
    DESCRIBE = paste("DESCRIBE", job$id, description(job$cron)),
    MATCH = {
      time <- args[[2L]]
      day <- time %/% 1440L
      status <- day_status(job$cron, day)
      rejected <- c(!time %% 60L %in% job$cron$fields[[1L]]$values,
        !time %/% 60L %% 24L %in% job$cron$fields[[2L]]$values,
        !status[["condition"]] && !status[["dom"]], !status[["month"]],
        !status[["condition"]] && !status[["dow"]], day %in% state$holidays)
      reasons <- c(field_names[c(1L, 2L, 3L, 4L, 5L)], "excluded")[rejected]
      joined(c("MATCH", job$id, datetime_text(time), if (length(reasons)) c("no", reasons) else "yes"))
    },
    NEXT =, PREV = {
      base <- args[[2L]]
      count <- args[[3L]]
      reverse <- command == "PREV"
      times <- if (reverse) fire_times(job, base - 527040L, base - 1L, state$holidays, TRUE, count) else {
        fire_times(job, base + 1L, base + 527040L, state$holidays, FALSE, count)
      }
      rows <- c(paste(command, job$id, length(times)), vapply(times, function(time) {
        paste(datetime_text(time), paste0(if (reverse) "-" else "+", span_text(abs(time - base))))
      }, character(1L)))
      if (length(times) < count) rows <- c(rows, "NONE")
      rows
    },
    COUNT = {
      times <- fire_times(job, args[[2L]], args[[3L]], state$holidays)
      paste("COUNT", job$id, "runs", length(times), "days", length(unique(times %/% 1440L)))
    },
    GAP = {
      times <- fire_times(job, args[[2L]], args[[2L]] + 44640L, state$holidays)
      if (length(times) < 2L) return(paste("GAP", job$id, "runs", length(times), "none"))
      gaps <- diff(times)
      longest <- which.max(gaps)
      values <- sort(unique(gaps), method = "radix")
      c(paste("GAP", job$id, "runs", length(times), "shortest", span_text(min(gaps)), "longest", span_text(max(gaps)),
              "from", datetime_text(times[longest]), "to", datetime_text(times[longest + 1L])),
        paste(span_text(values), tabulate(match(gaps, values), nbins = length(values))))
    },
    OVERLAP = {
      other <- args[[2L]]
      first <- fire_times(job, args[[3L]], args[[4L]], state$holidays)
      second <- fire_times(other, args[[3L]], args[[4L]], state$holidays)
      times <- first[first %in% second]
      result <- paste("OVERLAP", job$id, other$id, length(times))
      if (length(times)) result <- paste(result, "first", datetime_text(head(times, 1L)), "last", datetime_text(tail(times, 1L)))
      result
    },
    TIMELINE =, CONFLICTS = combined_report(state, command, args[[1L]], args[[2L]]),
    WEEK = week_report(state, args[[1L]], tokens[1L]),
    CALENDAR = calendar_report(state, job, args[[2L]], tokens[2L]),
    SIMULATE = simulation_report(state, args[[1L]], args[[2L]]),
    EXCLUDE =, INCLUDE = {
      day <- args[[1L]]
      if (command == "EXCLUDE") {
        if (day %in% state$holidays) fail("already excluded")
        state$holidays <- sort(c(state$holidays, day), method = "radix")
      } else {
        if (!day %in% state$holidays) fail("not excluded")
        state$holidays <- state$holidays[state$holidays != day]
      }
      paste(command, date_text(day), "holidays", length(state$holidays))
    },
    HOLIDAYS = c(paste("HOLIDAYS", length(state$holidays)), vapply(state$holidays, date_text, character(1L))))
}

calendar <- make_calendar()
state <- new.env(parent = emptyenv())
state$jobs <- list()
state$holidays <- integer()
input <- file("stdin", open = "r")
command_count <- as.integer(readLines(input, n = 1L, warn = FALSE))
for (index in seq_len(command_count)) {
  line <- readLines(input, n = 1L, warn = FALSE)
  rows <- tryCatch(execute(state, line), cron_error = function(error) paste("ERROR", error$message))
  cat(paste0(rows, "\n"), sep = "")
}
close(input)
