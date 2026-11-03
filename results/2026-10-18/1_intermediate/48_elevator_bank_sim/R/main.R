options(scipen = 999)
policies <- c("COST", "NEAREST", "ROUND", "ETA")
config_keys <- c(
  "FLOORS",
  "CARS",
  "CAPACITY",
  "DOOR",
  "START",
  "POLICY",
  "ZONES",
  "PARK",
  "PATIENCE",
  "BYPASS",
  "PERIOD",
  "LIMIT",
  "COMPARE"
)
argument_counts <- c(
  CALL = 3,
  CANCEL = 1,
  OUT = 1,
  IN = 1,
  HOLD = 2,
  FIRE = 1,
  RESET = 0,
  WHERE = 1,
  STATUS = 0
)
joined <- function(x) if (length(x)) paste(x, collapse = ",") else "-"
average <- function(total, count) {
  if (!count) {
    return("-")
  }
  cents <- floor(total * 100 / count)
  sprintf("%.0f.%02.0f", cents %/% 100, cents %% 100)
}
optional <- function(x) if (x < 0) "off" else as.character(x)
config_error <- function(message) {
  stop(structure(
    list(message = message, call = NULL),
    class = c("config_error", "error", "condition")
  ))
}
parse_config <- function(lines) {
  entries <- list()
  for (words in lines) {
    key <- words[1]
    if (!key %in% config_keys) {
      config_error(paste("unknown key", key))
    }
    if (key %in% names(entries)) {
      config_error(paste("duplicate key", key))
    }
    entries[key] <- list(words[-1])
  }
  for (key in config_keys[1:5]) {
    if (!key %in% names(entries)) config_error(paste("missing key", key))
  }
  cfg <- list(
    floors = 0,
    cars = 0,
    capacity = 0,
    door = 0,
    starts = numeric(),
    zones = list(),
    homes = numeric(),
    policy = "COST",
    park = -1,
    patience = -1,
    period = -1,
    bypass = 100,
    limit = 1000,
    compare = character()
  )
  bounded <- function(values, low, high) all(values >= low & values <= high)
  for (key in config_keys) {
    if (!key %in% names(entries)) {
      next
    }
    words <- entries[[key]]
    expected <- if (key %in% c("START", "ZONES")) {
      cfg$cars
    } else if (key == "PARK") {
      cfg$cars + 1
    } else {
      1
    }
    good_count <- if (key == "COMPARE") {
      length(words) >= 1 && length(words) <= 4
    } else {
      length(words) == expected
    }
    if (!good_count) {
      config_error(paste("wrong number of values for", key))
    }
    values <- if (!key %in% c("POLICY", "COMPARE", "ZONES")) {
      as.numeric(words)
    } else {
      numeric()
    }
    good <- TRUE
    if (key == "FLOORS") {
      cfg$floors <- values[1]
      good <- bounded(values, 2, 50)
    } else if (key == "CARS") {
      cfg$cars <- values[1]
      good <- bounded(values, 1, 8)
    } else if (key == "CAPACITY") {
      cfg$capacity <- values[1]
      good <- bounded(values, 1, 20)
    } else if (key == "DOOR") {
      cfg$door <- values[1]
      good <- bounded(values, 1, 9)
    } else if (key == "START") {
      cfg$starts <- values
      good <- bounded(values, 1, cfg$floors)
    } else if (key == "POLICY") {
      cfg$policy <- words[1]
      good <- words[1] %in% policies
    } else if (key == "ZONES") {
      cfg$zones <- lapply(strsplit(words, ":", fixed = TRUE), as.numeric)
      good <- all(vapply(
        cfg$zones,
        function(z) 1 <= z[1] && z[1] < z[2] && z[2] <= cfg$floors,
        logical(1)
      ))
    } else if (key == "PARK") {
      cfg$park <- values[1]
      cfg$homes <- values[-1]
      good <- bounded(cfg$park, 0, 100) && bounded(cfg$homes, 1, cfg$floors)
    } else if (key == "PATIENCE") {
      cfg$patience <- values[1]
      good <- bounded(values, 1, 1000)
    } else if (key == "BYPASS") {
      cfg$bypass <- values[1]
      good <- bounded(values, 50, 100)
    } else if (key == "PERIOD") {
      cfg$period <- values[1]
      good <- bounded(values, 1, 1000)
    } else if (key == "LIMIT") {
      cfg$limit <- values[1]
      good <- bounded(values, 1, 5000)
    } else {
      cfg$compare <- words
      good <- all(words %in% policies) && !anyDuplicated(words)
    }
    if (!good) config_error(paste("bad value for", key))
  }
  if (!length(cfg$zones)) {
    cfg$zones <- rep(list(c(1, cfg$floors)), cfg$cars)
  }
  for (i in seq_len(cfg$cars)) {
    zone <- cfg$zones[[i]]
    if (!bounded(cfg$starts[i], zone[1], zone[2])) {
      config_error(paste("car", i, "starts outside its zone"))
    }
    if (cfg$park >= 0 && !bounded(cfg$homes[i], zone[1], zone[2])) {
      config_error(paste("car", i, "home outside its zone"))
    }
  }
  cfg
}
config_header <- function(c) {
  lines <- sprintf(
    "config: floors=%d cars=%d capacity=%d door=%d policy=%s park=%s patience=%s bypass=%d period=%s limit=%d compare=%s",
    c$floors,
    c$cars,
    c$capacity,
    c$door,
    c$policy,
    optional(c$park),
    optional(c$patience),
    c$bypass,
    optional(c$period),
    c$limit,
    joined(c$compare)
  )
  for (i in seq_len(c$cars)) {
    z <- c$zones[[i]]
    home <- if (c$park < 0) "-" else as.character(c$homes[i])
    lines <- c(
      lines,
      sprintf(
        "E%d: start=%d zone=%d-%d home=%s",
        i,
        c$starts[i],
        z[1],
        z[2],
        home
      )
    )
  }
  lines
}
validate_events <- function(cfg, lines) {
  last <- groups <- 0
  fire <- FALSE
  out <- rep(FALSE, cfg$cars)
  accepted <- list()
  errors <- character()
  serves <- function(a, b) {
    any(vapply(
      cfg$zones,
      function(z) z[1] <= a && a <= z[2] && z[1] <= b && b <= z[2],
      logical(1)
    ))
  }
  for (line in lines) {
    w <- line$words
    time <- as.numeric(w[1])
    command <- w[2]
    args <- w[-c(1, 2)]
    message <- ""
    values <- numeric()
    if (!command %in% names(argument_counts)) {
      message <- paste("unknown command", command)
    } else if (length(args) != argument_counts[[command]]) {
      message <- paste("wrong number of arguments for", command)
    } else if (time < last) {
      message <- "time goes backwards"
    } else {
      values <- as.numeric(args)
      if (command == "CALL") {
        a <- values[1]
        b <- values[2]
        n <- values[3]
        if (a < 1 || a > cfg$floors || b < 1 || b > cfg$floors) {
          message <- "bad floor"
        } else if (a == b) {
          message <- "same floor"
        } else if (n < 1 || n > 99) {
          message <- "bad count"
        } else if (!serves(a, b)) {
          message <- paste0("no car serves ", a, "->", b)
        } else if (fire) {
          message <- "fire service active"
        }
      } else if (command %in% c("CANCEL", "WHERE")) {
        if (values[1] < 1 || values[1] > groups) message <- "unknown group"
      } else if (command %in% c("OUT", "IN")) {
        e <- values[1]
        if (e < 1 || e > cfg$cars) {
          message <- "bad car"
        } else if (command == "OUT" && out[e]) {
          message <- paste("car", e, "already out")
        } else if (command == "IN" && !out[e]) {
          message <- paste("car", e, "already in")
        }
      } else if (command == "HOLD") {
        if (values[1] < 1 || values[1] > cfg$cars) {
          message <- "bad car"
        } else if (values[2] < 1 || values[2] > 9) {
          message <- "bad ticks"
        }
      } else if (command == "FIRE") {
        if (values[1] < 1 || values[1] > cfg$floors) {
          message <- "bad floor"
        } else if (fire) {
          message <- "fire already active"
        }
      } else if (command == "RESET" && !fire) {
        message <- "fire not active"
      }
    }
    if (nzchar(message)) {
      errors <- c(errors, paste0("line ", line$number, ": ", message))
      next
    }
    last <- time
    if (command == "CALL") {
      groups <- groups + 1
    } else if (command == "OUT") {
      out[values[1]] <- TRUE
    } else if (command == "IN") {
      out[values[1]] <- FALSE
    } else if (command == "FIRE") {
      fire <- TRUE
    } else if (command == "RESET") {
      fire <- FALSE
    }
    accepted[[length(accepted) + 1]] <- list(
      time = time,
      command = command,
      values = values
    )
  }
  list(events = accepted, errors = errors)
}

simulate <- function(cfg, events, policy, logging = TRUE) {
  s <- new.env(parent = emptyenv())
  s$groups <- list()
  s$pending <- numeric()
  s$fire <- 0
  s$round <- 0
  s$time <- 0
  s$log <- character()
  s$status <- ""
  s$abandoned <- s$evacuated <- s$delivered <- 0
  s$wait <- s$travel <- s$max_wait <- 0
  s$cars <- lapply(seq_len(cfg$cars), function(i) {
    car <- new.env(parent = emptyenv())
    car$number <- i
    car$floor <- cfg$starts[i]
    car$zone <- cfg$zones[[i]]
    car$home <- if (cfg$park < 0) 0 else cfg$homes[i]
    car$direction <- car$door <- car$idle <- 0
    car$service <- TRUE
    car$passengers <- list()
    car$calls <- numeric()
    car$distance <- car$stops <- car$boarded <- car$busy <- car$energy <- 0
    car
  })
  emit <- function(...) {
    if (logging) s$log <- c(s$log, paste(s$time, paste(..., collapse = " ")))
  }
  load <- function(car) {
    sum(vapply(car$passengers, function(p) p$count, numeric(1)))
  }
  targets <- function(car) {
    unique(c(
      vapply(
        car$passengers,
        function(p) s$groups[[p$group]]$destination,
        numeric(1)
      ),
      vapply(car$calls, function(id) s$groups[[id]]$landing, numeric(1))
    ))
  }
  bypassing <- function(car) load(car) * 100 >= cfg$capacity * cfg$bypass
  cost <- function(car, group) {
    f <- car$floor
    d <- car$direction
    x <- group$landing
    if (policy == "NEAREST" || d == 0) {
      return(abs(f - x))
    }
    stops <- targets(car)
    if (group$direction == d && (x - f) * d >= 0) {
      distance <- abs(x - f)
      via <- sum((stops - f) * d > 0 & (x - stops) * d > 0)
    } else {
      turn <- if (d > 0) max(c(stops, f)) else min(c(stops, f))
      distance <- abs(f - turn) + abs(turn - x)
      via <- sum((stops - f) * d > 0)
    }
    if (policy == "COST") distance else distance + cfg$door * via + car$door
  }
  assign_call <- function(group, excluded = 0) {
    candidates <- Filter(
      function(car) {
        car$service &&
          car$number != excluded &&
          car$zone[1] <= group$landing &&
          group$landing <= car$zone[2] &&
          car$zone[1] <= group$destination &&
          group$destination <= car$zone[2]
      },
      s$cars
    )
    if (!length(candidates)) {
      return(FALSE)
    }
    if (policy == "ROUND") {
      after <- which(vapply(
        candidates,
        function(car) car$number > s$round,
        logical(1)
      ))
      chosen <- candidates[[if (length(after)) after[1] else 1]]
      s$round <- chosen$number
      emit(paste0("E", chosen$number), "ASSIGN", paste0("G", group$number))
    } else {
      costs <- vapply(candidates, function(car) cost(car, group), numeric(1))
      i <- which.min(costs)
      chosen <- candidates[[i]]
      emit(
        paste0("E", chosen$number),
        "ASSIGN",
        paste0("G", group$number),
        paste0("cost=", costs[i])
      )
    }
    if (group$car > 0) {
      old <- s$cars[[group$car]]
      old$calls <- old$calls[old$calls != group$number]
    }
    chosen$calls <- c(chosen$calls, group$number)
    group$car <- chosen$number
    TRUE
  }
  dispatch <- function(group) {
    if (!assign_call(group)) {
      s$pending <- c(s$pending, group$number)
      emit("PENDING", paste0("G", group$number))
    }
  }
  walk_away <- function(group, word) {
    if (group$car > 0) {
      car <- s$cars[[group$car]]
      car$calls <- car$calls[car$calls != group$number]
      group$car <- 0
    } else {
      s$pending <- s$pending[s$pending != group$number]
    }
    emit(word, paste0("G", group$number), paste0("x", group$waiting))
    group$lost <- group$lost + group$waiting
    s$abandoned <- s$abandoned + group$waiting
    group$waiting <- 0
  }
  execute <- function(event) {
    v <- event$values
    command <- event$command
    if (command == "CALL") {
      g <- new.env(parent = emptyenv())
      g$number <- length(s$groups) + 1
      g$landing <- v[1]
      g$destination <- v[2]
      g$count <- g$waiting <- v[3]
      g$time <- s$time
      g$direction <- sign(v[2] - v[1])
      g$car <- g$boarded <- g$delivered <- g$lost <- 0
      g$last_board <- g$last_alight <- g$wait <- g$travel <- 0
      g$cars <- numeric()
      s$groups[[g$number]] <- g
      emit(
        "CALL",
        paste0("G", g$number),
        paste0(g$landing, "->", g$destination),
        paste0("x", g$count)
      )
      dispatch(g)
    } else if (command == "CANCEL") {
      g <- s$groups[[v[1]]]
      if (g$waiting > 0) {
        walk_away(g, "CANCEL")
      } else {
        emit("CANCEL", paste0("G", g$number), "ignored")
      }
    } else if (command == "OUT") {
      car <- s$cars[[v[1]]]
      car$service <- FALSE
      emit(paste0("E", car$number), "OUT")
      calls <- car$calls
      car$calls <- numeric()
      for (id in calls) {
        g <- s$groups[[id]]
        g$car <- 0
        dispatch(g)
      }
    } else if (command == "IN") {
      car <- s$cars[[v[1]]]
      car$service <- TRUE
      car$idle <- s$time
      emit(paste0("E", car$number), "IN")
      pending <- s$pending
      s$pending <- numeric()
      for (id in pending) {
        if (!assign_call(s$groups[[id]])) s$pending <- c(s$pending, id)
      }
    } else if (command == "HOLD") {
      car <- s$cars[[v[1]]]
      if (car$door > 0) {
        car$door <- car$door + v[2]
        emit(paste0("E", car$number), "HOLD", car$door)
      } else {
        emit(paste0("E", car$number), "HOLD", "ignored")
      }
    } else if (command == "FIRE") {
      s$fire <- v[1]
      emit("FIRE", s$fire)
      for (g in s$groups) {
        if (g$waiting > 0) walk_away(g, "ABANDON")
      }
    } else if (command == "RESET") {
      s$fire <- 0
      emit("RESET")
      for (car in s$cars) {
        car$idle <- s$time
      }
    } else if (command == "WHERE") {
      g <- s$groups[[v[1]]]
      place <- if (!g$waiting) {
        "-"
      } else if (g$car) {
        paste0("E", g$car)
      } else {
        "pending"
      }
      riding <- character()
      for (car in s$cars) {
        count <- sum(vapply(
          car$passengers,
          function(p) if (p$group == g$number) p$count else 0,
          numeric(1)
        ))
        if (count > 0) riding <- c(riding, paste0("E", car$number, "x", count))
      }
      emit(
        "WHERE",
        paste0("G", g$number),
        paste0("waiting=", g$waiting),
        paste0("car=", place),
        paste0("riding=", joined(riding)),
        paste0("delivered=", g$delivered),
        paste0("lost=", g$lost)
      )
    } else {
      for (car in s$cars) {
        stops <- sort(unique(vapply(
          car$passengers,
          function(p) s$groups[[p$group]]$destination,
          numeric(1)
        )))
        direction <- if (car$direction > 0) {
          "up"
        } else if (car$direction < 0) {
          "down"
        } else {
          "idle"
        }
        emit(
          "STATUS",
          paste0("E", car$number),
          paste0("floor=", car$floor),
          paste0("dir=", direction),
          paste0("door=", car$door),
          paste0("load=", load(car)),
          paste0("stops=", joined(stops)),
          paste0(
            "calls=",
            joined(
              if (length(car$calls)) paste0("G", car$calls) else character()
            )
          ),
          paste0("service=", if (car$service) "in" else "out")
        )
      }
      emit(
        "STATUS",
        paste0(
          "pending=",
          joined(if (length(s$pending)) paste0("G", s$pending) else character())
        )
      )
    }
  }
  choose_direction <- function(car) {
    f <- car$floor
    d <- car$direction
    stops <- targets(car)
    here <- if (bypassing(car)) {
      numeric()
    } else {
      Filter(function(id) s$groups[[id]]$landing == f, car$calls)
    }
    if (
      d != 0 &&
        (any((stops - f) * d > 0) ||
          any(vapply(
            here,
            function(id) s$groups[[id]]$direction == d,
            logical(1)
          )))
    ) {
      return(d)
    }
    if (length(here)) {
      return(s$groups[[here[1]]]$direction)
    }
    if (d != 0 && any((stops - f) * d < 0)) {
      return(-d)
    }
    if (d == 0 && length(car$calls)) {
      return(sign(s$groups[[car$calls[1]]]$landing - f))
    }
    0
  }
  deliver <- function(p) {
    g <- s$groups[[p$group]]
    wait <- p$boarded - g$time
    travel <- s$time - g$time
    g$delivered <- g$delivered + p$count
    g$last_alight <- s$time
    g$wait <- g$wait + wait * p$count
    g$travel <- g$travel + travel * p$count
    s$delivered <- s$delivered + p$count
    s$wait <- s$wait + wait * p$count
    s$travel <- s$travel + travel * p$count
    s$max_wait <- max(s$max_wait, wait)
  }
  open_doors <- function(car) {
    emit(paste0("E", car$number), "OPEN", car$floor)
    car$door <- cfg$door
    car$stops <- car$stops + 1
    car$energy <- car$energy + 2
    riding <- list()
    for (p in car$passengers) {
      g <- s$groups[[p$group]]
      if (g$destination == car$floor) {
        emit(
          paste0("E", car$number),
          "ALIGHT",
          paste0("G", g$number),
          paste0("x", p$count)
        )
        deliver(p)
      } else if (s$fire > 0) {
        emit(
          paste0("E", car$number),
          "EVACUATE",
          paste0("G", g$number),
          paste0("x", p$count)
        )
        g$lost <- g$lost + p$count
        s$evacuated <- s$evacuated + p$count
      } else {
        riding[[length(riding) + 1]] <- p
      }
    }
    car$passengers <- riding
    if (s$fire > 0) {
      return(invisible(NULL))
    }
    heading <- choose_direction(car)
    if (heading != 0) {
      car$direction <- heading
    }
    boarding <- Filter(
      function(id) {
        g <- s$groups[[id]]
        g$landing == car$floor && g$direction == heading
      },
      car$calls
    )
    for (id in boarding) {
      g <- s$groups[[id]]
      count <- min(cfg$capacity - load(car), g$waiting)
      if (count > 0) {
        car$passengers[[length(car$passengers) + 1]] <- list(
          group = id,
          count = count,
          boarded = s$time
        )
        car$boarded <- car$boarded + count
        g$waiting <- g$waiting - count
        g$boarded <- g$boarded + count
        g$last_board <- s$time
        g$cars <- unique(c(g$cars, car$number))
        emit(
          paste0("E", car$number),
          "BOARD",
          paste0("G", id),
          paste0("x", count)
        )
      }
      if (!g$waiting) {
        car$calls <- car$calls[car$calls != id]
        g$car <- 0
      } else {
        emit(
          paste0("E", car$number),
          "LEFT",
          paste0("G", id),
          paste0("x", g$waiting)
        )
        assign_call(g, car$number)
      }
    }
  }
  move <- function(car, step) {
    car$energy <- car$energy + if (step > 0) 3 + load(car) else 1
    car$distance <- car$distance + 1
    car$floor <- car$floor + step
  }
  advance <- function(car) {
    previous_floor <- car$floor
    if (car$door > 0) {
      car$door <- car$door - 1
    }
    if (!car$door) {
      if (s$fire > 0) {
        heading <- sign(s$fire - car$floor)
        stopping <- heading == 0 && length(car$passengers) > 0
      } else {
        heading <- choose_direction(car)
        stopping <- any(vapply(
          car$passengers,
          function(p) s$groups[[p$group]]$destination == car$floor,
          logical(1)
        )) ||
          (!bypassing(car) &&
            any(vapply(
              car$calls,
              function(id) {
                g <- s$groups[[id]]
                g$landing == car$floor && g$direction == heading
              },
              logical(1)
            )))
      }
      if (stopping) {
        open_doors(car)
      } else if (heading != 0) {
        car$direction <- heading
        move(car, heading)
      } else {
        if (car$direction != 0) {
          emit(paste0("E", car$number), "IDLE", car$floor)
          car$direction <- 0
          car$idle <- s$time
        }
        if (
          !s$fire &&
            car$service &&
            car$home > 0 &&
            car$floor != car$home &&
            s$time - car$idle >= cfg$park
        ) {
          move(car, sign(car$home - car$floor))
          if (car$floor == car$home) {
            emit(paste0("E", car$number), "PARK", car$home)
          }
        }
      }
    }
    if (car$door > 0 || car$floor != previous_floor) car$busy <- car$busy + 1
  }
  settled <- function(car) {
    if (car$door > 0 || length(car$passengers) || length(car$calls)) {
      return(FALSE)
    }
    if (s$fire > 0) {
      car$floor == s$fire
    } else {
      !car$service || !car$home || car$floor == car$home
    }
  }
  index <- 1
  repeat {
    if (cfg$patience >= 0) {
      for (g in s$groups) {
        if (g$waiting > 0 && s$time == g$time + cfg$patience) {
          walk_away(g, "ABANDON")
        }
      }
    }
    while (index <= length(events) && events[[index]]$time == s$time) {
      execute(events[[index]])
      index <- index + 1
    }
    for (car in s$cars) {
      advance(car)
    }
    if (index > length(events) && all(vapply(s$cars, settled, logical(1)))) {
      s$status <- "end"
      emit("END")
      break
    }
    if (s$time == cfg$limit) {
      s$status <- "abort"
      emit("ABORT")
      break
    }
    s$time <- s$time + 1
  }
  s
}
averages <- function(s) {
  paste0(
    "avg_wait=",
    average(s$wait, s$delivered),
    " avg_travel=",
    average(s$travel, s$delivered),
    " max_wait=",
    if (s$delivered) s$max_wait else "-"
  )
}
breakdown <- function(label, groups) {
  sum_field <- function(field) {
    sum(vapply(groups, function(g) g[[field]], numeric(1)))
  }
  delivered <- sum_field("delivered")
  sprintf(
    "%s: groups=%d passengers=%.0f delivered=%.0f avg_wait=%s",
    label,
    length(groups),
    sum_field("count"),
    delivered,
    average(sum_field("wait"), delivered)
  )
}
report <- function(s, cfg) {
  lines <- character()
  for (g in s$groups) {
    wait <- if (g$boarded == g$count) {
      as.character(g$last_board - g$time)
    } else {
      "-"
    }
    travel <- if (g$delivered == g$count) {
      as.character(g$last_alight - g$time)
    } else {
      "-"
    }
    lines <- c(
      lines,
      sprintf(
        "G%d t=%.0f %.0f->%.0f n=%.0f delivered=%.0f lost=%.0f wait=%s travel=%s cars=%s",
        g$number,
        g$time,
        g$landing,
        g$destination,
        g$count,
        g$delivered,
        g$lost,
        wait,
        travel,
        joined(sort(g$cars))
      )
    )
  }
  for (car in s$cars) {
    tenths <- floor(car$busy * 1000 / (s$time + 1))
    lines <- c(
      lines,
      sprintf(
        "E%d distance=%.0f stops=%.0f boarded=%.0f busy=%.0f util=%.0f.%.0f%% energy=%.0f",
        car$number,
        car$distance,
        car$stops,
        car$boarded,
        car$busy,
        tenths %/% 10,
        tenths %% 10,
        car$energy
      )
    )
  }
  for (floor in sort(unique(vapply(
    s$groups,
    function(g) g$landing,
    numeric(1)
  )))) {
    lines <- c(
      lines,
      breakdown(
        paste0("F", floor),
        Filter(function(g) g$landing == floor, s$groups)
      )
    )
  }
  if (cfg$period > 0) {
    for (k in sort(unique(vapply(
      s$groups,
      function(g) g$time %/% cfg$period,
      numeric(1)
    )))) {
      start <- k * cfg$period
      lines <- c(
        lines,
        breakdown(
          paste0("P", k, " ", start, "-", start + cfg$period - 1),
          Filter(function(g) g$time %/% cfg$period == k, s$groups)
        )
      )
    }
  }
  passengers <- sum(vapply(s$groups, function(g) g$count, numeric(1)))
  c(
    lines,
    sprintf(
      "summary: groups=%d passengers=%.0f delivered=%.0f abandoned=%.0f evacuated=%.0f %s end=%.0f",
      length(s$groups),
      passengers,
      s$delivered,
      s$abandoned,
      s$evacuated,
      averages(s),
      s$time
    )
  )
}
outcome <- function(scenario) {
  s <- scenario$simulation
  if (is.null(s)) {
    "invalid"
  } else if (s$status == "abort") {
    "aborted"
  } else if (!s$delivered) {
    "empty"
  } else {
    "ranked"
  }
}
lines <- readLines(file("stdin"), warn = FALSE)
index <- 2
output <- character()
scenarios <- list()
for (q in seq_len(as.integer(lines[1]))) {
  name <- strsplit(lines[index], " ", fixed = TRUE)[[1]][2]
  index <- index + 1
  settings <- event_lines <- list()
  while (lines[index] != "END") {
    words <- strsplit(lines[index], " ", fixed = TRUE)[[1]]
    if (substr(words[1], 1, 1) %in% as.character(0:9)) {
      event_lines[[length(event_lines) + 1]] <- list(
        number = index,
        words = words
      )
    } else {
      settings[[length(settings) + 1]] <- words
    }
    index <- index + 1
  }
  index <- index + 1
  scenario <- list(name = name, config = NULL, simulation = NULL)
  output <- c(output, paste0("== ", name, " =="))
  parsed <- tryCatch(
    list(config = parse_config(settings)),
    config_error = function(e) list(error = conditionMessage(e))
  )
  if (!is.null(parsed$error)) {
    output <- c(output, paste0("error: ", parsed$error))
  } else {
    cfg <- parsed$config
    scenario$config <- cfg
    checked <- validate_events(cfg, event_lines)
    output <- c(output, config_header(cfg), checked$errors)
    s <- simulate(cfg, checked$events, cfg$policy)
    scenario$simulation <- s
    output <- c(output, s$log, report(s, cfg))
    for (policy in cfg$compare) {
      rerun <- simulate(cfg, checked$events, policy, FALSE)
      output <- c(
        output,
        sprintf(
          "compare %s: delivered=%.0f %s end=%.0f status=%s",
          policy,
          rerun$delivered,
          averages(rerun),
          rerun$time,
          rerun$status
        )
      )
    }
  }
  scenarios[[q]] <- scenario
}
output <- c(output, "== ranking ==")
ranked <- Filter(function(x) outcome(x) == "ranked", scenarios)
if (length(ranked) > 1) {
  for (i in 2:length(ranked)) {
    j <- i
    while (j > 1) {
      a <- ranked[[j]]$simulation
      b <- ranked[[j - 1]]$simulation
      left <- a$wait * b$delivered
      right <- b$wait * a$delivered
      before <- left < right ||
        (left == right && a$travel * b$delivered < b$travel * a$delivered)
      if (!before) {
        break
      }
      temp <- ranked[[j - 1]]
      ranked[[j - 1]] <- ranked[[j]]
      ranked[[j]] <- temp
      j <- j - 1
    }
  }
}
for (i in seq_along(ranked)) {
  x <- ranked[[i]]
  output <- c(
    output,
    paste0(
      i,
      ". ",
      x$name,
      " policy=",
      x$config$policy,
      " ",
      averages(x$simulation)
    )
  )
}
for (x in scenarios) {
  if (outcome(x) != "ranked") {
    output <- c(output, paste("-", x$name, outcome(x)))
  }
}
output <- c(output, "== policies ==")
for (policy in policies) {
  runs <- Filter(function(x) x$config$policy == policy, ranked)
  if (!length(runs)) {
    next
  }
  count <- sum(vapply(runs, function(x) x$simulation$delivered, numeric(1)))
  wait <- sum(vapply(runs, function(x) x$simulation$wait, numeric(1)))
  travel <- sum(vapply(runs, function(x) x$simulation$travel, numeric(1)))
  output <- c(
    output,
    sprintf(
      "%s: runs=%d avg_wait=%s avg_travel=%s",
      policy,
      length(runs),
      average(wait, count),
      average(travel, count)
    )
  )
}
cat(paste(output, collapse = "\n"), "\n", sep = "")
