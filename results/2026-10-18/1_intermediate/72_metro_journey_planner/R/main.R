state <- new.env(parent = emptyenv())
state$stations <- list()
state$lines <- list()
state$walks <- list()
state$closed <- list()
state$tariff <- NULL

say <- function(...) cat(paste0(...), "\n", sep = "")
fail <- function(message) {
  stop(structure(list(message = message, call = NULL), class = c("MetroError", "error", "condition")))
}
ordered <- function(x) sort(unique(x), method = "radix")
keys <- function(x) ordered(names(x))
minutes <- function(text) {
  parts <- as.integer(strsplit(text, ":", fixed = TRUE)[[1]])
  parts[[1]] * 60L + parts[[2]]
}
clock <- function(value) sprintf("%02d:%02d", as.integer(value %/% 60L), as.integer(value %% 60L))
segment <- function(a, b) paste(ordered(c(a, b)), collapse = "-")
blocked <- function(a, b) !is.null(state$closed[[segment(a, b)]])
station_check <- function(id) {
  if (is.null(state$stations[[id]])) fail(paste("unknown station", id))
}
line_check <- function(id) {
  if (is.null(state$lines[[id]])) fail(paste("unknown line", id))
}
open_check <- function(id) {
  if (state$stations[[id]]$closed) fail(paste("station", id, "is closed"))
}
journey_check <- function(origin, destination) {
  station_check(origin)
  station_check(destination)
  if (origin == destination) fail("origin and destination are the same")
  open_check(origin)
  open_check(destination)
}
trips <- function(line) (line$last - line$first) %/% line$headway + 1L
duration <- function(line) tail(line$offsets, 1L)
directions <- function(line) {
  list(list(stops = line$stops, offsets = line$offsets),
       list(stops = rev(line$stops), offsets = duration(line) - rev(line$offsets)))
}
next_train <- function(line, offset, ready) {
  difference <- max(0L, ready - line$first - line$delay - offset)
  q <- (difference + line$headway - 1L) %/% line$headway
  if (q < trips(line)) q else NULL
}
train_time <- function(line, q, offset) line$first + line$delay + q * line$headway + offset
running_lines <- function() Filter(function(line) !line$suspended, state$lines[keys(state$lines)])
ride_leg <- function(line, terminal, from, start, to, finish, stops) {
  list(kind = "ride", line = line, terminal = terminal, from = from, start = start,
       to = to, finish = finish, stops = stops)
}
walk_leg <- function(from, start, to, finish) list(kind = "walk", from = from, start = start, to = to, finish = finish)
update_label <- function(labels, destination, time, journey) {
  old <- labels[[destination]]
  if (!is.null(old) && old$time <= time) return(FALSE)
  labels[[destination]] <- list(time = time, journey = journey)
  TRUE
}
earliest <- function(origin, departure) {
  labels <- new.env(parent = emptyenv())
  labels[[origin]] <- list(time = departure, journey = list())
  settled <- character()
  lines <- running_lines()
  repeat {
    candidates <- setdiff(ordered(ls(labels)), settled)
    if (!length(candidates)) break
    times <- vapply(candidates, function(id) labels[[id]]$time, numeric(1))
    u <- candidates[[which.min(times)]]
    settled <- c(settled, u)
    arrival <- labels[[u]]$time
    journey <- labels[[u]]$journey
    ready <- arrival + if (u == origin) 0L else state$stations[[u]]$transfer
    for (line in lines) {
      if (!(u %in% line$stops)) next
      for (direction in directions(line)) {
        stops <- direction$stops
        offsets <- direction$offsets
        i <- match(u, stops)
        if (i == length(stops)) next
        q <- next_train(line, offsets[[i]], ready)
        if (is.null(q)) next
        boarding <- train_time(line, q, offsets[[i]])
        for (j in (i + 1L):length(stops)) {
          if (blocked(stops[[j - 1L]], stops[[j]])) break
          if (state$stations[[stops[[j]]]]$closed) next
          time <- train_time(line, q, offsets[[j]])
          leg <- ride_leg(line$id, tail(stops, 1L), u, boarding, stops[[j]], time, j - i)
          update_label(labels, stops[[j]], time, c(journey, list(leg)))
        }
      }
    }
    for (v in keys(state$walks[[u]])) {
      time <- arrival + state$walks[[u]][[v]]
      if (state$stations[[v]]$closed || time > 1440L) next
      update_label(labels, v, time, c(journey, list(walk_leg(u, arrival, v, time))))
    }
  }
  as.list(labels)
}
walk_step <- function(labels, selected, marked) {
  selected <- ordered(selected)
  snapshot <- lapply(selected, function(u) labels[[u]])
  names(snapshot) <- selected
  for (u in selected) {
    arrival <- snapshot[[u]]$time
    journey <- snapshot[[u]]$journey
    for (v in keys(state$walks[[u]])) {
      time <- arrival + state$walks[[u]][[v]]
      if (state$stations[[v]]$closed || time > 1440L) next
      if (update_label(labels, v, time, c(journey, list(walk_leg(u, arrival, v, time))))) marked <- union(marked, v)
    }
  }
  marked
}
round_search <- function(origin, departure) {
  labels <- new.env(parent = emptyenv())
  labels[[origin]] <- list(time = departure, journey = list())
  marked <- walk_step(labels, origin, origin)
  result <- list(as.list(labels))
  lines <- running_lines()
  while (length(marked)) {
    previous <- as.list(labels)
    previous_marked <- marked
    labels <- list2env(previous, parent = emptyenv())
    marked <- character()
    selected <- character()
    for (line in lines) {
      for (direction in directions(line)) {
        stops <- direction$stops
        offsets <- direction$offsets
        boarded <- NULL
        b <- NULL
        boarding <- NULL
        journey <- list()
        for (j in seq_along(stops)) {
          u <- stops[[j]]
          if (j > 1L && blocked(stops[[j - 1L]], u)) boarded <- NULL
          if (state$stations[[u]]$closed) next
          if (!is.null(boarded)) {
            time <- train_time(line, boarded, offsets[[j]])
            leg <- ride_leg(line$id, tail(stops, 1L), stops[[b]], boarding, u, time, j - b)
            if (update_label(labels, u, time, c(journey, list(leg)))) {
              selected <- union(selected, u)
              marked <- union(marked, u)
            }
          }
          if (j == length(stops) || !(u %in% previous_marked)) next
          arrival <- previous[[u]]$time
          ready <- arrival + if (u == origin) 0L else state$stations[[u]]$transfer
          candidate <- next_train(line, offsets[[j]], ready)
          if (!is.null(candidate) && (is.null(boarded) || candidate < boarded)) {
            boarded <- candidate
            b <- j
            boarding <- train_time(line, candidate, offsets[[j]])
            journey <- previous[[u]]$journey
          }
        }
      }
    }
    marked <- walk_step(labels, selected, marked)
    result[[length(result) + 1L]] <- as.list(labels)
  }
  result
}
ride_count <- function(journey) sum(vapply(journey, function(leg) leg$kind == "ride", logical(1)))
print_journey <- function(heading, departure, label) {
  arrival <- label$time
  journey <- label$journey
  walks <- sum(vapply(journey, function(leg) leg$kind == "walk", logical(1)))
  say(heading, " ", clock(departure), " -> ", clock(arrival), " total ", arrival - departure,
      " rides ", ride_count(journey), " walks ", walks)
  previous_end <- departure
  for (leg in journey) {
    if (leg$kind == "ride") {
      say("RIDE ", leg$line, " toward ", leg$terminal, " ", leg$from, " ", clock(leg$start),
          " -> ", leg$to, " ", clock(leg$finish), " wait ", leg$start - previous_end, " stops ", leg$stops)
    } else if (leg$kind == "walk") {
      say("WALK ", leg$from, " ", clock(leg$start), " -> ", leg$to, " ", clock(leg$finish))
    } else {
      say("STAY ", leg$station, " ", clock(leg$start), " -> ", clock(leg$finish))
    }
    previous_end <- leg$finish
  }
}
print_fare <- function(origin, destination, time_text, fare_class, journey) {
  tariff <- state$tariff
  half <- function(x) ((x + 19L) %/% 20L) * 10L
  cap <- if (fare_class == "CHILD") half(tariff$discount) else tariff$discount
  tickets <- list()
  previous_end <- NULL
  for (leg in journey) {
    if (leg$kind != "ride") next
    line <- state$lines[[leg$line]]
    for (direction in directions(line)) if (tail(direction$stops, 1L) == leg$terminal) break
    stops <- direction$stops
    selected <- stops[match(leg$from, stops):match(leg$to, stops)]
    zone_count <- length(unique(vapply(selected, function(id) state$stations[[id]]$zone, integer(1))))
    price <- tariff$prices[[min(zone_count, length(tariff$prices))]]
    if (fare_class == "CHILD") price <- half(price)
    discount <- if (!is.null(previous_end) && leg$start - previous_end <= tariff$window) min(cap, price) else 0L
    tickets[[length(tickets) + 1L]] <- list(line = leg$line, from = leg$from, to = leg$to,
      zones = zone_count, price = price, discount = discount, pay = price - discount)
    previous_end <- leg$finish
  }
  total <- sum(vapply(tickets, function(ticket) ticket$pay, numeric(1)))
  say("FARE ", origin, " ", destination, " ", time_text, " ", fare_class, " rides ", length(tickets), " total ", total)
  for (ticket in tickets) say("TICKET ", ticket$line, " ", ticket$from, " ", ticket$to, " zones ", ticket$zones,
      " price ", ticket$price, " discount ", ticket$discount, " pay ", ticket$pay)
}
search_command <- function(command, args) {
  origin <- args[[1]]
  destination <- args[[2]]
  journey_check(origin, destination)
  departure <- if (length(args) >= 3L) minutes(args[[3]]) else NULL
  if (command == "FARE") {
    if (!(args[[4]] %in% c("ADULT", "CHILD"))) fail(paste("unknown fare class", args[[4]]))
    if (is.null(state$tariff)) fail("no tariff")
  } else if (command == "PROFILE" && departure > minutes(args[[4]])) {
    fail(paste("empty interval", args[[3]], args[[4]]))
  }
  if (command %in% c("ROUTE", "FARE")) {
    label <- earliest(origin, departure)[[destination]]
    if (is.null(label)) {
      say(command, " ", paste(args, collapse = " "), " unreachable")
    } else if (command == "ROUTE") {
      print_journey(paste("ROUTE", origin, destination), departure, label)
    } else {
      print_fare(origin, destination, args[[3]], args[[4]], label$journey)
    }
  } else if (command %in% c("FEWEST", "PARETO")) {
    all <- round_search(origin, departure)
    options <- integer()
    for (i in seq_along(all)) {
      label <- all[[i]][[destination]]
      if (!is.null(label) && (i == 1L || is.null(all[[i - 1L]][[destination]]) || label$time < all[[i - 1L]][[destination]]$time)) options <- c(options, i)
    }
    if (command == "FEWEST") {
      if (length(options)) {
        i <- options[[1]]
        print_journey(paste("FEWEST", origin, destination, "trips", i - 1L), departure, all[[i]][[destination]])
      } else {
        say("FEWEST ", paste(args, collapse = " "), " unreachable")
      }
    } else {
      say("PARETO ", paste(args, collapse = " "), " options ", length(options))
      for (i in options) print_journey(paste("OPTION trips", i - 1L), departure, all[[i]][[destination]])
    }
  } else if (command %in% c("LASTTRAIN", "ARRIVEBY")) {
    start <- if (command == "LASTTRAIN") 1439L else departure - 1L
    heading <- paste(command, origin, destination)
    if (command == "ARRIVEBY") heading <- paste(heading, "by", args[[3]])
    if (start >= 0L) {
      for (time in seq.int(start, 0L)) {
        label <- earliest(origin, time)[[destination]]
        if (!is.null(label) && (command == "LASTTRAIN" || label$time <= departure)) {
          print_journey(heading, time, label)
          return(invisible(NULL))
        }
      }
    }
    say(heading, " none")
  } else if (command == "PROFILE") {
    finish <- minutes(args[[4]])
    times <- seq.int(departure, finish)
    arrivals <- vapply(times, function(time) {
      label <- earliest(origin, time)[[destination]]
      if (is.null(label)) Inf else label$time
    }, numeric(1))
    selected <- which(is.finite(arrivals) & c(arrivals[-length(arrivals)] < arrivals[-1L], TRUE))
    say("PROFILE ", paste(args, collapse = " "), " count ", length(selected))
    for (i in selected) say(clock(times[[i]]), " -> ", clock(arrivals[[i]]), " total ", arrivals[[i]] - times[[i]])
  }
}
get_direction <- function(line, toward) {
  for (direction in directions(line)) if (tail(direction$stops, 1L) == toward) return(direction)
  fail(paste(toward, "is not a terminal of line", line$id))
}
execute <- function(text) {
  words <- strsplit(text, " ", fixed = TRUE)[[1]]
  command <- words[[1]]
  args <- words[-1]
  a <- if (length(args)) args[[1]] else NULL
  b <- if (length(args) >= 2L) args[[2]] else NULL
  switch(command,
    STATION = {
      if (!is.null(state$stations[[a]])) fail(paste("station", a, "already exists"))
      state$stations[[a]] <- list(zone = as.integer(b), name = args[[3]], transfer = 0L, closed = FALSE)
      state$walks[[a]] <- list()
      say("STATION ", a, " zone ", b, " ", args[[3]])
    },
    LINE = {
      if (!is.null(state$lines[[a]])) fail(paste("line", a, "already exists"))
      stops <- args[seq.int(5L, length(args), by = 2L)]
      for (id in stops) station_check(id)
      seen <- character()
      for (id in stops) {
        if (id %in% seen) fail(paste("station", id, "appears twice on line", a))
        seen <- c(seen, id)
      }
      first <- minutes(b)
      last <- minutes(args[[3]])
      if (first > last) fail(paste("line", a, "first departure is after last departure"))
      offsets <- c(0L, cumsum(as.integer(args[seq.int(6L, length(args) - 1L, by = 2L)])))
      if (last + tail(offsets, 1L) > 1440L) fail(paste("line", a, "runs past 24:00"))
      line <- list(id = a, first = first, last = last, headway = as.integer(args[[4]]),
                   stops = stops, offsets = offsets, delay = 0L, suspended = FALSE)
      state$lines[[a]] <- line
      say("LINE ", a, " stops ", length(stops), " time ", duration(line), " trips ", trips(line))
    },
    TRANSFER = {
      station_check(a)
      state$stations[[a]]$transfer <- as.integer(b)
      say("TRANSFER ", a, " ", b)
    },
    WALK = {
      station_check(a)
      station_check(b)
      if (a == b) fail(paste("walk from", a, "to itself"))
      old <- state$walks[[a]][[b]]
      state$walks[[a]][[b]] <- as.integer(args[[3]])
      state$walks[[b]][[a]] <- as.integer(args[[3]])
      say("WALK ", paste(args, collapse = " "), if (is.null(old)) "" else paste0(" was ", old))
    },
    TARIFF = {
      prices <- as.integer(args[-c(1L, 2L)])
      if (any(diff(prices) < 0L)) fail("tariff prices must not decrease")
      state$tariff <- list(discount = as.integer(a), window = as.integer(b), prices = prices)
      say("TARIFF zones ", length(prices), " discount ", a, " window ", b)
    },
    CLOSE = closure_command(args, TRUE),
    OPEN = closure_command(args, FALSE),
    DELAY = {
      line_check(a)
      if (state$lines[[a]]$last + as.integer(b) + duration(state$lines[[a]]) > 1440L) fail(paste("line", a, "runs past 24:00"))
      state$lines[[a]]$delay <- as.integer(b)
      say("DELAY ", a, " ", b)
    },
    SUSPEND = suspend_command(a, TRUE),
    RESUME = suspend_command(a, FALSE),
    ROUTE = search_command(command, args),
    FEWEST = search_command(command, args),
    PARETO = search_command(command, args),
    FARE = search_command(command, args),
    LASTTRAIN = search_command(command, args),
    ARRIVEBY = search_command(command, args),
    PROFILE = search_command(command, args),
    VIA = {
      origin <- a
      via <- b
      destination <- args[[3]]
      time_text <- args[[4]]
      for (id in c(origin, via, destination)) station_check(id)
      if (origin == destination) fail("origin and destination are the same")
      if (via == origin || via == destination) fail(paste("via station", via, "must differ from origin and destination"))
      for (id in c(origin, via, destination)) open_check(id)
      departure <- minutes(time_text)
      first <- earliest(origin, departure)[[via]]
      second <- NULL
      if (!is.null(first)) {
        ready <- first$time + state$stations[[via]]$transfer
        second <- earliest(via, ready)[[destination]]
      }
      if (!is.null(second)) {
        stay <- list(kind = "stay", station = via, start = first$time, finish = ready)
        journey <- c(first$journey, list(stay), second$journey)
        print_journey(paste("VIA", origin, via, destination), departure, list(time = second$time, journey = journey))
      } else {
        say("VIA ", paste(args, collapse = " "), " unreachable")
      }
    },
    REACH = {
      station_check(a)
      open_check(a)
      departure <- minutes(b)
      labels <- earliest(a, departure)
      selected <- keys(labels)
      times <- vapply(selected, function(id) labels[[id]]$time, numeric(1))
      selected <- selected[order(times, selected, method = "radix")]
      selected <- selected[vapply(selected, function(id) labels[[id]]$time <= departure + as.integer(args[[3]]), logical(1))]
      say("REACH ", paste(args, collapse = " "), " count ", length(selected))
      for (id in selected) {
        label <- labels[[id]]
        say(id, " ", state$stations[[id]]$name, " ", clock(label$time), " ", label$time - departure,
            " rides ", ride_count(label$journey))
      }
    },
    TIMETABLE = {
      station_check(a)
      line_check(b)
      line <- state$lines[[b]]
      if (!(a %in% line$stops)) fail(paste("station", a, "is not on line", b))
      toward <- args[[3]]
      direction <- get_direction(line, toward)
      if (a == toward) fail(paste("no departures from", a, "toward", toward))
      if (line$suspended) fail(paste("line", b, "is suspended"))
      open_check(a)
      offset <- direction$offsets[[match(a, direction$stops)]]
      times <- train_time(line, seq_len(trips(line)) - 1L, offset)
      times <- head(times[times >= minutes(args[[4]])], as.integer(args[[5]]))
      say("TIMETABLE ", a, " ", b, " toward ", toward, " ", args[[4]], " next ", length(times),
          if (length(times)) paste0(" ", paste(vapply(times, clock, character(1)), collapse = " ")) else "")
    },
    DEPARTURES = station_trains(command, args),
    ARRIVALS = station_trains(command, args),
    TRIP = {
      line_check(a)
      line <- state$lines[[a]]
      direction <- get_direction(line, b)
      if (line$suspended) fail(paste("line", a, "is suspended"))
      q <- next_train(line, 0L, minutes(args[[3]]))
      if (is.null(q)) {
        say("TRIP ", a, " toward ", b, " ", args[[3]], " none")
      } else {
        say("TRIP ", a, " toward ", b, " ", args[[3]], " trip ", q + 1L, " departs ", clock(train_time(line, q, 0L)))
        for (i in seq_along(direction$stops)) {
          id <- direction$stops[[i]]
          suffix <- if (state$stations[[id]]$closed) " closed" else ""
          if (i > 1L && blocked(direction$stops[[i - 1L]], id)) suffix <- paste0(suffix, " blocked")
          say(clock(train_time(line, q, direction$offsets[[i]])), " ", id, suffix)
        }
      }
    },
    SHOWLINE = {
      line_check(a)
      line <- state$lines[[a]]
      say("SHOWLINE ", a, " ", if (line$suspended) "suspended" else "running", " first ", clock(line$first),
          " last ", clock(line$last), " headway ", line$headway, " delay ", line$delay, " trips ", trips(line))
      for (i in seq_along(line$stops)) {
        id <- line$stops[[i]]
        suffix <- if (state$stations[[id]]$closed) " closed" else ""
        if (i > 1L && blocked(line$stops[[i - 1L]], id)) suffix <- paste0(suffix, " blocked")
        say(line$offsets[[i]], " ", id, " zone ", state$stations[[id]]$zone, suffix)
      }
    },
    INFO = {
      station_check(a)
      station <- state$stations[[a]]
      say("INFO ", a, " ", station$name, " zone ", station$zone, " transfer ", station$transfer,
          " ", if (station$closed) "closed" else "open")
      lines <- keys(state$lines)
      lines <- lines[vapply(lines, function(id) a %in% state$lines[[id]]$stops, logical(1))]
      say("LINES ", if (length(lines)) paste(lines, collapse = " ") else "none")
      neighbors <- keys(state$walks[[a]])
      walks <- vapply(neighbors, function(v) paste(v, state$walks[[a]][[v]]), character(1))
      say("WALKS ", if (length(walks)) paste(walks, collapse = " ") else "none")
    },
    STATUS = {
      say("STATUS stations ", length(state$stations), " lines ", length(state$lines), " walks ", sum(lengths(state$walks)) %/% 2L)
      for (id in keys(state$stations)) if (state$stations[[id]]$closed) say("CLOSED ", id)
      segments <- unname(state$closed)
      if (length(segments)) {
        first <- vapply(segments, function(pair) pair[[1]], character(1))
        second <- vapply(segments, function(pair) pair[[2]], character(1))
        for (i in order(first, second, method = "radix")) say("CLOSED ", first[[i]], "-", second[[i]])
      }
      for (id in keys(state$lines)) if (state$lines[[id]]$suspended) say("SUSPENDED ", id)
      for (id in keys(state$lines)) if (state$lines[[id]]$delay != 0L) say("DELAYED ", id, " ", state$lines[[id]]$delay)
    }
  )
}
closure_command <- function(args, close) {
  a <- args[[1]]
  station_check(a)
  command <- if (close) "CLOSE" else "OPEN"
  if (length(args) == 2L) {
    b <- args[[2]]
    station_check(b)
    key <- segment(a, b)
    if (close) {
      affected <- character()
      for (id in keys(state$lines)) {
        stops <- state$lines[[id]]$stops
        for (i in seq_len(length(stops) - 1L)) {
          if (segment(stops[[i]], stops[[i + 1L]]) == key) {
            affected <- c(affected, id)
            break
          }
        }
      }
      if (!length(affected)) fail(paste("no segment", paste0(a, "-", b)))
      if (!is.null(state$closed[[key]])) fail(paste("segment", paste0(a, "-", b), "is already closed"))
      state$closed[[key]] <- ordered(c(a, b))
      say("CLOSE ", a, "-", b, " lines ", paste(affected, collapse = " "))
    } else {
      if (is.null(state$closed[[key]])) fail(paste("segment", paste0(a, "-", b), "is not closed"))
      state$closed[[key]] <- NULL
      say("OPEN ", a, "-", b)
    }
  } else {
    current <- state$stations[[a]]$closed
    if (close && current) fail(paste("station", a, "is already closed"))
    if (!close && !current) fail(paste("station", a, "is not closed"))
    state$stations[[a]]$closed <- close
    say(command, " ", a)
  }
}
suspend_command <- function(id, suspend) {
  line_check(id)
  if (suspend && state$lines[[id]]$suspended) fail(paste("line", id, "is already suspended"))
  if (!suspend && !state$lines[[id]]$suspended) fail(paste("line", id, "is not suspended"))
  state$lines[[id]]$suspended <- suspend
  say(if (suspend) "SUSPEND " else "RESUME ", id)
}
station_trains <- function(command, args) {
  station <- args[[1]]
  station_check(station)
  open_check(station)
  entries <- list()
  for (line in running_lines()) {
    if (!(station %in% line$stops)) next
    dirs <- directions(line)
    for (d in seq_along(dirs)) {
      direction <- dirs[[d]]
      stops <- direction$stops
      i <- match(station, stops)
      if (if (command == "DEPARTURES") i == length(stops) else i == 1L) next
      for (q in seq_len(trips(line)) - 1L) {
        time <- train_time(line, q, direction$offsets[[i]])
        if (time >= minutes(args[[2]])) {
          terminal <- if (command == "DEPARTURES") tail(stops, 1L) else stops[[1]]
          entries[[length(entries) + 1L]] <- list(time = time, line = line$id, direction = d, terminal = terminal)
        }
      }
    }
  }
  if (length(entries)) {
    times <- vapply(entries, function(entry) entry$time, numeric(1))
    lines <- vapply(entries, function(entry) entry$line, character(1))
    dirs <- vapply(entries, function(entry) entry$direction, integer(1))
    entries <- head(entries[order(times, lines, dirs, method = "radix")], as.integer(args[[3]]))
  }
  say(command, " ", station, " ", args[[2]], " count ", length(entries))
  for (entry in entries) say(clock(entry$time), " ", entry$line,
      if (command == "DEPARTURES") " toward " else " from ", entry$terminal)
}

input <- file("stdin", "r")
count <- as.integer(readLines(input, n = 1L, warn = FALSE))
for (i in seq_len(count)) {
  text <- readLines(input, n = 1L, warn = FALSE)
  tryCatch(execute(text), MetroError = function(error) say("ERROR ", conditionMessage(error)))
}
