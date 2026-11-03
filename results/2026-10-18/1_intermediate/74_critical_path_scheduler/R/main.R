options(scipen = 999)
say <- function(...) cat(paste0(...), "\n", sep = "")
fail <- function(message) stop(structure(list(message = message, call = NULL), class = c("ScheduleError", "error", "condition")))
ordered <- function(x) sort(unique(x), method = "radix")
state <- new.env(parent = emptyenv())
state$tasks <- list()
state$deps <- list()
state$capacities <- list()
state$start <- NULL
state$deadline <- NULL
state$holidays <- integer()
state$baseline <- NULL
analysis_commands <- c("CPM", "CRITICAL", "SLACK", "DRAG", "STATS", "CALENDAR", "GANTT", "LEVEL", "LOAD", "PERTSUM", "CRASH", "WHATIF", "BASELINE", "VARIANCE")
task_names <- function() ordered(names(state$tasks))
require_task <- function(name) {
  if (is.null(state$tasks[[name]])) fail(paste("unknown task", name))
}
duration <- function(task) task$base - task$used
predecessors <- function(name) ordered(vapply(Filter(function(d) d$b == name, state$deps), function(d) d$a, character(1)))
successors <- function(name) ordered(vapply(Filter(function(d) d$a == name, state$deps), function(d) d$b, character(1)))
dependency <- function(a, b) state$deps[[paste0(a, ":", b)]]
topology <- function() {
  remaining <- task_names()
  result <- character()
  repeat {
    eligible <- remaining[vapply(remaining, function(t) !length(intersect(predecessors(t), remaining)), logical(1))]
    if (!length(eligible)) break
    name <- eligible[[1]]
    remaining <- setdiff(remaining, name)
    result <- c(result, name)
  }
  if (!length(remaining)) return(list(order = result, cycle = NULL))
  walk <- remaining[[1]]
  repeat {
    following <- intersect(predecessors(tail(walk, 1L)), remaining)[[1]]
    i <- match(following, walk)
    if (!is.na(i)) {
      cycle <- c(walk[[i]], rev(if (i < length(walk)) walk[(i + 1L):length(walk)] else character()))
      first <- match(ordered(cycle)[[1]], cycle)
      cycle <- c(cycle[first:length(cycle)], if (first > 1L) cycle[seq_len(first - 1L)] else character())
      return(list(order = result, cycle = paste(c(cycle, cycle[[1]]), collapse = " -> ")))
    }
    walk <- c(walk, following)
  }
}
margin <- function(a, b, schedule) {
  dep <- dependency(a, b)
  switch(dep$kind, FS = schedule[[b]]$ES - schedule[[a]]$EF - dep$lag,
    SS = schedule[[b]]$ES - schedule[[a]]$ES - dep$lag,
    FF = schedule[[b]]$EF - schedule[[a]]$EF - dep$lag)
}
compute <- function(overrides = list()) {
  order <- topology()$order
  result <- list()
  for (name in order) {
    task <- state$tasks[[name]]
    d <- overrides[[name]]
    if (is.null(d)) d <- duration(task)
    start <- task$day
    for (a in predecessors(name)) {
      dep <- dependency(a, name)
      value <- switch(dep$kind, FS = result[[a]]$EF + dep$lag,
        SS = result[[a]]$ES + dep$lag, FF = result[[a]]$EF + dep$lag - d)
      start <- max(start, value)
    }
    result[[name]] <- list(DUR = d, ES = start, EF = start + d)
  }
  total <- max(vapply(result, function(v) v$EF, numeric(1)))
  for (name in rev(order)) {
    value <- result[[name]]
    finish <- total
    for (b in successors(name)) {
      dep <- dependency(name, b)
      candidate <- switch(dep$kind, FS = result[[b]]$LS - dep$lag,
        SS = result[[b]]$LS - dep$lag + value$DUR, FF = result[[b]]$LF - dep$lag)
      finish <- min(finish, candidate)
    }
    value$LF <- finish
    value$LS <- finish - value$DUR
    value$TF <- value$LS - value$ES
    result[[name]] <- value
  }
  for (name in task_names()) {
    floats <- vapply(successors(name), function(b) margin(name, b, result), numeric(1))
    result[[name]]$FF <- min(c(total - result[[name]]$EF, floats))
  }
  list(schedule = result, total = total)
}
critical <- function(schedule) task_names()[vapply(task_names(), function(name) schedule[[name]]$TF == 0L, logical(1))]
critical_paths <- function(schedule) {
  selected <- critical(schedule)
  edges <- Filter(function(d) d$a %in% selected && d$b %in% selected && margin(d$a, d$b, schedule) == 0L, state$deps)
  roots <- selected[!vapply(selected, function(name) any(vapply(edges, function(d) d$b == name, logical(1))), logical(1))]
  paths <- list()
  visit <- function(path) {
    children <- ordered(vapply(Filter(function(d) d$a == tail(path, 1L), edges), function(d) d$b, character(1)))
    if (!length(children)) paths[[length(paths) + 1L]] <<- path else for (name in children) visit(c(path, name))
  }
  for (name in roots) visit(name)
  paths
}
signed <- function(value) sprintf("%+d", as.integer(value))
decimal <- function(numerator, denominator) {
  hundredths <- (numerator * 100) %/% denominator
  sprintf("%d.%02d", as.integer(hundredths %/% 100), as.integer(hundredths %% 100))
}
date_value <- function(text) {
  parts <- as.integer(strsplit(text, "-", fixed = TRUE)[[1]])
  year <- parts[[1]]
  month <- parts[[2]]
  day <- parts[[3]]
  leap <- year %% 4L == 0L && (year %% 100L != 0L || year %% 400L == 0L)
  lengths <- c(31L, if (leap) 29L else 28L, 31L, 30L, 31L, 30L, 31L, 31L, 30L, 31L, 30L, 31L)
  if (month < 1L || month > 12L || day < 1L || day > lengths[[month]]) fail(paste("invalid date", text))
  as.integer(as.Date(text, format = "%Y-%m-%d"))
}
weekday <- function(date) (date + 3L) %% 7L
date_text <- function(date) paste(format(as.Date(date, origin = "1970-01-01"), "%Y-%m-%d"), c("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")[[weekday(date) + 1L]])
working <- function(date) weekday(date) < 5L && !(date %in% state$holidays)
calendar <- function(schedule, total) {
  dates <- integer()
  current <- state$start
  while (length(dates) < total) {
    if (working(current)) dates <- c(dates, current)
    current <- current + 1L
  }
  names <- task_names()
  starts <- vapply(names, function(name) schedule[[name]]$ES, numeric(1))
  for (name in names[order(starts, names, method = "radix")]) {
    say(name, " ", date_text(dates[[schedule[[name]]$ES + 1L]]), " - ", date_text(dates[[schedule[[name]]$EF]]))
  }
  first <- dates[[1]]
  finish <- tail(dates, 1L)
  say("project ", date_text(first), " - ", date_text(finish), ", ", total, " working days, ", finish - first + 1L, " calendar days")
  if (!is.null(state$deadline)) {
    lower <- min(finish, state$deadline)
    upper <- max(finish, state$deadline)
    days <- if (lower == upper) 0L else sum(vapply(seq.int(lower + 1L, upper), working, logical(1)))
    description <- if (finish <= state$deadline) paste0("met, ", days, " working days to spare") else paste0("missed by ", days, " working days")
    say("deadline ", date_text(state$deadline), " ", description)
  }
  holidays <- sort(state$holidays[state$holidays >= first & state$holidays <= finish & weekday(state$holidays) < 5L])
  say("holidays in span: ", if (length(holidays)) paste(vapply(holidays, date_text, character(1)), collapse = ", ") else "none")
}
usage <- function(schedule, resource, total) {
  daily <- rep(0L, total)
  for (name in task_names()) {
    task <- state$tasks[[name]]
    if (task$resource != resource) next
    days <- seq.int(schedule[[name]]$ES + 1L, schedule[[name]]$EF)
    daily[days] <- daily[days] + task$units
  }
  daily
}
level <- function(limit, schedule, total) {
  capacity <- function(r) if (is.null(state$capacities[[r]])) limit else state$capacities[[r]]
  for (name in task_names()) {
    task <- state$tasks[[name]]
    if (task$units > capacity(task$resource)) fail(paste("capacity", capacity(task$resource), "too small for", name))
  }
  decided <- list()
  order <- character()
  daily <- list()
  use <- function(r, days) {
    if (is.null(daily[[r]])) return(rep(0L, length(days)))
    values <- daily[[r]][days + 1L]
    values[is.na(values)] <- 0L
    values
  }
  while (length(decided) < length(state$tasks)) {
    eligible <- setdiff(task_names(), names(decided))
    eligible <- eligible[vapply(eligible, function(t) all(predecessors(t) %in% names(decided)), logical(1))]
    latest <- vapply(eligible, function(t) schedule[[t]]$LS, numeric(1))
    name <- eligible[[which.min(latest)]]
    task <- state$tasks[[name]]
    d <- duration(task)
    start <- task$day
    for (a in predecessors(name)) {
      dep <- dependency(a, name)
      value <- switch(dep$kind, FS = decided[[a]]$F + dep$lag,
        SS = decided[[a]]$S + dep$lag, FF = decided[[a]]$F + dep$lag - d)
      start <- max(start, value)
    }
    repeat {
      days <- seq.int(start, start + d - 1L)
      if (all(use(task$resource, days) + task$units <= capacity(task$resource))) break
      start <- start + 1L
    }
    decided[[name]] <- list(S = start, F = start + d)
    values <- daily[[task$resource]]
    if (length(values) < start + d) values <- c(values, rep(0L, start + d - length(values)))
    values[days + 1L] <- values[days + 1L] + task$units
    daily[[task$resource]] <- values
    order <- c(order, name)
  }
  finish <- max(vapply(decided, function(v) v$F, numeric(1)))
  say("level capacity ", limit, ": duration ", total, " -> ", finish)
  for (name in order) say(name, " start ", decided[[name]]$S, " finish ", decided[[name]]$F,
      " shift ", decided[[name]]$S - schedule[[name]]$ES)
  resources <- ordered(vapply(state$tasks, function(t) t$resource, character(1)))
  for (r in resources) say("resource ", r, " capacity ", capacity(r), " peak ", max(usage(schedule, r, total)), " -> ", max(c(0L, daily[[r]])))
}
crash <- function(budget, initial) {
  remaining <- budget
  steps <- 0L
  final <- initial
  repeat {
    current <- compute()
    candidates <- critical(current$schedule)
    candidates <- candidates[vapply(candidates, function(name) {
      task <- state$tasks[[name]]
      !is.null(task$crash_limit) && task$used < task$crash_limit && compute(setNames(list(duration(task) - 1L), name))$total < current$total
    }, logical(1))]
    if (!length(candidates)) {
      reason <- "no candidate"
      break
    }
    costs <- vapply(candidates, function(name) state$tasks[[name]]$cost, integer(1))
    name <- candidates[[which.min(costs)]]
    task <- state$tasks[[name]]
    if (task$cost > remaining) {
      reason <- "insufficient budget"
      break
    }
    before <- duration(task)
    state$tasks[[name]]$used <- task$used + 1L
    remaining <- remaining - task$cost
    steps <- steps + 1L
    final <- compute()$total
    say("step ", steps, ": ", name, " ", before, " -> ", before - 1L, ", cost ", task$cost, ", project ", final)
  }
  say("crash done: ", steps, " days, cost ", budget - remaining, ", project ", initial, " -> ", final,
      ", budget left ", remaining, ", ", reason)
}
analyze <- function(command, args) {
  if (!length(state$tasks)) fail("no tasks")
  cycle <- topology()$cycle
  if (!is.null(cycle)) fail(paste("cycle", cycle))
  if (command == "CALENDAR" && is.null(state$start)) fail("no start date")
  if (command == "LOAD" && !any(vapply(state$tasks, function(t) t$resource == args[[1]], logical(1)))) fail(paste("unknown resource", args[[1]]))
  if (command == "WHATIF") require_task(args[[1]])
  if (command == "VARIANCE" && is.null(state$baseline)) fail("no baseline")
  result <- compute()
  schedule <- result$schedule
  total <- result$total
  names <- task_names()
  switch(command,
    CPM = {
      width <- max(4L, nchar(names))
      say(sprintf(paste0("%-", width, "s"), "TASK"), paste(sprintf("%5s", c("DUR", "ES", "EF", "LS", "LF", "TF", "FF")), collapse = ""))
      for (name in names) {
        values <- vapply(c("DUR", "ES", "EF", "LS", "LF", "TF", "FF"), function(key) schedule[[name]][[key]], numeric(1))
        say(sprintf(paste0("%-", width, "s"), name), paste(sprintf("%5d", as.integer(values)), collapse = ""), if (schedule[[name]]$TF == 0L) " *" else "")
      }
      say("project duration ", total)
    },
    CRITICAL = display_paths(command, schedule),
    PERTSUM = display_paths(command, schedule),
    SLACK = {
      floats <- vapply(names, function(name) schedule[[name]]$TF, numeric(1))
      for (value in sort(unique(floats))) say("float ", value, ": ", paste(names[floats == value], collapse = " "))
    },
    DRAG = {
      for (name in critical(schedule)) say(name, " drag ", total - compute(setNames(list(0L), name))$total)
    },
    STATS = {
      count <- length(critical(schedule))
      kinds <- vapply(c("FS", "SS", "FF"), function(kind) sum(vapply(state$deps, function(d) d$kind == kind, logical(1))), numeric(1))
      say("tasks ", length(names), ", critical ", count, ", dependencies ", length(state$deps),
          " (FS ", kinds[[1]], ", SS ", kinds[[2]], ", FF ", kinds[[3]], ")")
      resources <- ordered(vapply(state$tasks, function(t) t$resource, character(1)))
      work <- vapply(resources, function(r) {
        amount <- sum(vapply(state$tasks, function(t) if (t$resource == r) duration(t) * t$units else 0L, numeric(1)))
        paste(r, amount)
      }, character(1))
      say("work ", paste(work, collapse = ", "))
      sum_float <- sum(vapply(schedule, function(v) v$TF, numeric(1)))
      say("float total ", sum_float, ", average ", decimal(sum_float, length(names)))
      say("duration ", total, ", critical share ", decimal(100L * count, length(names)), "%")
    },
    CALENDAR = calendar(schedule, total),
    GANTT = {
      if (total > 60L) fail(paste0("chart too wide (", total, " days)"))
      width <- max(nchar(names))
      say(strrep(" ", width), " |", paste((seq_len(total) - 1L) %% 10L, collapse = ""), "|")
      starts <- vapply(names, function(name) schedule[[name]]$ES, numeric(1))
      for (name in names[order(starts, names, method = "radix")]) {
        value <- schedule[[name]]
        bar <- vapply(seq_len(total) - 1L, function(day) {
          if (day >= value$ES && day < value$EF) {
            if (value$TF == 0L) "=" else "-"
          } else if (day >= value$EF && day < value$LF) "." else " "
        }, character(1))
        say(sprintf(paste0("%-", width, "s"), name), " |", paste(bar, collapse = ""), "|")
      }
    },
    LEVEL = level(as.integer(args[[1]]), schedule, total),
    LOAD = {
      resource <- args[[1]]
      values <- usage(schedule, resource, total)
      say("load ", resource, ": ", paste(values, collapse = " "))
      say("peak ", max(values), " on day ", which.max(values) - 1L)
      if (!is.null(state$capacities[[resource]])) say("capacity ", state$capacities[[resource]], " exceeded on ", sum(values > state$capacities[[resource]]), " days")
    },
    CRASH = crash(as.integer(args[[1]]), total),
    WHATIF = {
      name <- args[[1]]
      after <- compute(setNames(list(as.integer(args[[2]])), name))
      say("whatif ", name, " ", duration(state$tasks[[name]]), " -> ", args[[2]], ": project ", total, " -> ", after$total)
      for (t in names) {
        fields <- c("ES", "EF", "TF")
        fields <- fields[vapply(fields, function(key) schedule[[t]][[key]] != after$schedule[[t]][[key]], logical(1))]
        if (length(fields)) say(t, paste(vapply(fields, function(key) paste0(" ", key, " ", schedule[[t]][[key]], "->", after$schedule[[t]][[key]]), character(1)), collapse = ""))
      }
      before_critical <- critical(schedule)
      after_critical <- critical(after$schedule)
      if (!identical(before_critical, after_critical)) say("critical ", paste(before_critical, collapse = " "), " -> ", paste(after_critical, collapse = " "))
    },
    BASELINE = {
      saved <- lapply(names, function(name) c(schedule[[name]]$ES, schedule[[name]]$EF))
      names(saved) <- names
      state$baseline <- list(total = total, tasks = saved)
      say("baseline saved: ", length(names), " tasks, duration ", total)
    },
    VARIANCE = {
      old <- state$baseline
      say("variance: duration ", old$total, " -> ", total, " (", signed(total - old$total), ")")
      printed <- FALSE
      for (name in ordered(c(names, names(old$tasks)))) {
        if (is.null(state$tasks[[name]])) {
          say(name, " removed")
        } else if (is.null(old$tasks[[name]])) {
          say(name, " new")
        } else if (any(c(schedule[[name]]$ES, schedule[[name]]$EF) != old$tasks[[name]])) {
          say(name, " start ", signed(schedule[[name]]$ES - old$tasks[[name]][[1]]), " finish ", signed(schedule[[name]]$EF - old$tasks[[name]][[2]]))
        } else next
        printed <- TRUE
      }
      if (!printed) say("no task changes")
    }
  )
}
display_paths <- function(command, schedule) {
  paths <- critical_paths(schedule)
  if (command == "CRITICAL") say("critical paths: ", length(paths))
  for (path in paths) {
    notation <- paste(path, collapse = " -> ")
    if (command == "CRITICAL") {
      say(notation)
    } else {
      estimates <- lapply(path, function(name) {
        task <- state$tasks[[name]]
        if (is.null(task$estimate)) rep(duration(task), 3L) else task$estimate
      })
      expected <- sum(vapply(estimates, function(e) e[[1]] + 4L * e[[2]] + e[[3]], numeric(1)))
      variance <- sum(vapply(estimates, function(e) (e[[3]] - e[[1]])^2, numeric(1)))
      say(notation, ": expected ", decimal(expected, 6L), " variance ", decimal(variance, 36L))
    }
  }
}
execute <- function(line) {
  words <- strsplit(line, " ", fixed = TRUE)[[1]]
  command <- words[[1]]
  args <- words[-1]
  if (command %in% analysis_commands) {
    analyze(command, args)
    return(invisible(NULL))
  }
  name <- if (length(args)) args[[1]] else NULL
  if (command == "TASK") {
    if (!is.null(state$tasks[[name]])) fail(paste("task", name, "already exists"))
    state$tasks[[name]] <- list(base = as.integer(args[[2]]), resource = args[[3]], units = as.integer(args[[4]]),
      day = 0L, crash_limit = NULL, cost = NULL, used = 0L, estimate = NULL)
    say("task ", name, " added")
  } else if (command %in% c("DEP", "UNDEP")) {
    a <- name
    b <- args[[2]]
    require_task(a)
    require_task(b)
    key <- paste0(a, ":", b)
    if (command == "DEP") {
      if (a == b) fail(paste("self dependency", a))
      if (!is.null(state$deps[[key]])) fail(paste("dependency", a, "->", b, "already exists"))
      state$deps[[key]] <- list(a = a, b = b, kind = args[[3]], lag = as.integer(args[[4]]))
      say("dependency ", a, " -> ", b, " ", args[[3]], signed(as.integer(args[[4]])), " added")
    } else {
      if (is.null(state$deps[[key]])) fail(paste("no dependency", a, "->", b))
      state$deps[[key]] <- NULL
      say("dependency ", a, " -> ", b, " removed")
    }
  } else if (command == "CAPACITY") {
    state$capacities[[name]] <- as.integer(args[[2]])
    say("capacity ", name, " ", args[[2]])
  } else if (command %in% c("START", "HOLIDAY", "DEADLINE")) {
    date <- date_value(name)
    if (command == "START") state$start <- date else if (command == "DEADLINE") state$deadline <- date else {
      if (date %in% state$holidays) fail(paste("duplicate holiday", name))
      state$holidays <- c(state$holidays, date)
    }
    say(tolower(command), " ", date_text(date))
  } else if (command == "LIST") {
    say("tasks ", length(state$tasks), ", dependencies ", length(state$deps), ", holidays ", length(state$holidays))
    for (name in task_names()) {
      task <- state$tasks[[name]]
      preds <- predecessors(name)
      say(name, " duration ", duration(task), " resource ", task$resource, " units ", task$units,
          " preds ", if (length(preds)) paste(preds, collapse = " ") else "none")
    }
  } else {
    require_task(name)
    task <- state$tasks[[name]]
    switch(command,
      REMOVE = {
        remove <- vapply(state$deps, function(d) d$a == name || d$b == name, logical(1))
        state$deps <- state$deps[!remove]
        state$tasks[[name]] <- NULL
        say("task ", name, " removed with ", sum(remove), " dependencies")
      },
      NOTBEFORE = {
        state$tasks[[name]]$day <- as.integer(args[[2]])
        say("notbefore ", name, " ", args[[2]])
      },
      CRASHCOST = {
        maximum <- as.integer(args[[2]])
        cost <- as.integer(args[[3]])
        if (maximum >= task$base) fail(paste("crash limit too large for", name))
        if (maximum < task$used) fail(paste("crash limit below used days for", name))
        state$tasks[[name]]$crash_limit <- maximum
        state$tasks[[name]]$cost <- cost
        say("crash ", name, " max ", maximum, " cost ", cost)
      },
      UNCRASH = {
        say("uncrash ", name, " restored ", task$used, " days")
        state$tasks[[name]]$used <- 0L
      },
      PERT = {
        estimate <- as.integer(args[-1])
        if (any(diff(estimate) < 0L)) fail("invalid estimate")
        state$tasks[[name]]$estimate <- estimate
        say("pert ", name, " expected ", decimal(estimate[[1]] + 4L * estimate[[2]] + estimate[[3]], 6L),
            " variance ", decimal((estimate[[3]] - estimate[[1]])^2, 36L))
      },
      SHOW = {
        say("task ", name, " duration ", duration(task), " resource ", task$resource, " units ", task$units,
            if (task$day != 0L) paste0(" notbefore ", task$day) else "")
        preds <- vapply(predecessors(name), function(a) {
          d <- dependency(a, name)
          paste0(a, " ", d$kind, signed(d$lag))
        }, character(1))
        succs <- vapply(successors(name), function(b) {
          d <- dependency(name, b)
          paste0(b, " ", d$kind, signed(d$lag))
        }, character(1))
        say("preds: ", if (length(preds)) paste(preds, collapse = ", ") else "none")
        say("succs: ", if (length(succs)) paste(succs, collapse = ", ") else "none")
        say(if (is.null(task$crash_limit)) "crash: none" else paste("crash: max", task$crash_limit, "used", task$used, "cost", task$cost))
        say(if (is.null(task$estimate)) "pert: none" else paste("pert:", paste(task$estimate, collapse = " ")))
        if (!is.null(topology()$cycle)) {
          say("schedule: unavailable")
        } else {
          value <- compute()$schedule[[name]]
          fields <- vapply(c("ES", "EF", "LS", "LF", "TF", "FF"), function(key) paste(key, value[[key]]), character(1))
          say("schedule: ", paste(fields, collapse = " "), if (value$TF == 0L) " critical" else "")
        }
      },
      IMPACT = {
        seen <- name
        at <- 1L
        while (at <= length(seen)) {
          seen <- union(seen, successors(seen[[at]]))
          at <- at + 1L
        }
        affected <- ordered(setdiff(seen, name))
        say("impact ", name, ": ", if (length(affected)) paste(affected, collapse = " ") else "none")
      }
    )
  }
}

input <- file("stdin", "r")
count <- as.integer(readLines(input, n = 1L, warn = FALSE))
for (i in seq_len(count)) {
  line <- readLines(input, n = 1L, warn = FALSE)
  tryCatch(execute(line), ScheduleError = function(error) say("error: ", conditionMessage(error)))
}
